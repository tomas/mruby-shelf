module Shelf

  module Multipart

    CHUNK_SIZE = 8192.freeze
    CONTENT_TYPE = 'CONTENT_TYPE'.freeze
    BOUNDARY_REGEX = %r|\Amultipart/.*boundary=\"?([^\";,]+)\"?|i
    # MAX_BODY_LENGTH = (1024 * 1024 * 10).freeze # 10 MB

    def self.parse(io, env)
      params = nil

      boundary = env[CONTENT_TYPE][BOUNDARY_REGEX, 1]
      return nil unless boundary

      # puts "Initializing with boundary: #{boundary}"
      parts, reader = {}, Reader.new(boundary)

      reader.on_error do |err|
        # puts err.inspect
        raise err
      end

      reader.on_part do |part|
        parts[part.name] = part

        part.on_data do |data|
          part.data << data
        end

        part.on_end do
          part.ended = true
        end
      end

      io.rewind
      # bytes_read = 0
      while bytes = io.read(CHUNK_SIZE) # and bytes_read < MAX_BODY_LENGTH
        reader.write(bytes)
        # bytes_read += bytes.length
      end

      parts
    end

    class NotMultipartError < StandardError; end;

    # A low level parser for multipart messages,
    # based on the node-formidable parser.
    class Parser

      def initialize
        @boundary = nil
        @boundary_chars = nil
        @lookbehind = nil
        @state = :parser_uninitialized
        @index = 0  # Index into boundary or header
        @flags = {}
        @marks = {} # Keep track of different parts
        @callbacks = {}
      end

      # Initializes the parser, using the given boundary
      def init_with_boundary(boundary)
        @boundary = "\r\n--" + boundary
        @lookbehind = "\0"*(@boundary.length + 8)
        @state = :start

        @boundary_chars = {}
        @boundary.each_byte do |b|
          @boundary_chars[b.chr] = true
        end
      end

      # Registers a callback to be called when the
      # given event occurs. Each callback is expected to
      # take three parameters: buffer, start_index, and end_index.
      # All of these parameters may be null, depending on the callback.
      # Valid callbacks are:
      # :end
      # :header_field
      # :header_value
      # :header_end
      # :headers_end
      # :part_begin
      # :part_data
      # :part_end
      def on(event, &callback)
        @callbacks[event] = callback
      end

      # Writes data to the parser.
      # Returns the number of bytes parsed.
      # In practise, this means that if the return value
      # is less than the buffer length, a parse error occured.
      def write(buffer)
        i = 0
        buffer_length = buffer.length
        index = @index
        flags = @flags.dup
        state = @state
        lookbehind = @lookbehind
        boundary = @boundary
        boundary_chars = @boundary_chars
        boundary_length = @boundary.length
        boundary_end = boundary_length - 1

        while i < buffer_length
          c = buffer[i, 1]
          case state
            when :parser_uninitialized
              return i;
            when :start
              index = 0;
              state = :start_boundary
            when :start_boundary # Differs in that it has no preceeding \r\n
              if index == boundary_length - 2
                return i unless c == "\r"
                index += 1
              elsif index - 1 == boundary_length - 2
                return i unless c == "\n"
                # Boundary read successfully, begin next part
                callback(:part_begin)
                state = :header_field_start
              else
                return i unless c == boundary[index+2, 1] # Unexpected character
                index += 1
              end
              i += 1
            when :header_field_start
              state = :header_field
              @marks[:header_field] = i
              index = 0
            when :header_field
              if c == "\r"
                @marks.delete :header_field
                state = :headers_almost_done
              else
                index += 1
                unless c == "-" # Skip hyphens
                  if c == ":"
                    return i if index == 1 # Empty header field
                    data_callback(:header_field, buffer, i, :clear => true)
                    state = :header_value_start
                  else
                    cl = c.downcase
                    return i if cl < "a" || cl > "z"
                  end
                end
              end
              i += 1
            when :header_value_start
              if c == " " # Skip spaces
                i += 1
              else
                @marks[:header_value] = i
                state = :header_value
              end
            when :header_value
              if c == "\r"
                data_callback(:header_value, buffer, i, :clear => true)
                callback(:header_end)
                state = :header_value_almost_done
              end
              i += 1
            when :header_value_almost_done
              return i unless c == "\n"
              state = :header_field_start
              i += 1
            when :headers_almost_done
              return i unless c == "\n"
              callback(:headers_end)
              state = :part_data_start
              i += 1
            when :part_data_start
              state = :part_data
              @marks[:part_data] = i
            when :part_data
              prev_index = index

              if index == 0
                # Boyer-Moore derived algorithm to safely skip non-boundary data
                # See http://debuggable.com/posts/parsing-file-uploads-at-500-
                # mb-s-with-node-js:4c03862e-351c-4faa-bb67-4365cbdd56cb
                while i + boundary_length <= buffer_length
                  break if boundary_chars.has_key? buffer[i + boundary_end].chr
                  i += boundary_length
                end
                c = buffer[i, 1]
              end

              if index < boundary_length
                if boundary[index, 1] == c
                  if index == 0
                    data_callback(:part_data, buffer, i, :clear => true)
                  end
                  index += 1
                else # It was not the boundary we found, after all
                  index = 0
                end
              elsif index == boundary_length
                index += 1
                if c == "\r"
                  flags[:part_boundary] = true
                elsif c == "-"
                  flags[:last_boundary] = true
                else # We did not find a boundary after all
                  index = 0
                end
              elsif index - 1 == boundary_length
                if flags[:part_boundary]
                  index = 0
                  if c == "\n"
                    flags.delete :part_boundary
                    callback(:part_end)
                    callback(:part_begin)
                    state = :header_field_start
                    i += 1
                    next # Ugly way to break out of the case statement
                  end
                elsif flags[:last_boundary]
                  if c == "-"
                    callback(:part_end)
                    callback(:end)
                    state = :end
                  else
                    index = 0 # False alarm
                  end
                else
                  index = 0
                end
              end

              if index > 0
                # When matching a possible boundary, keep a lookbehind
                # reference in case it turns out to be a false lead
                lookbehind[index-1] = c
              elsif prev_index > 0
                # If our boundary turns out to be rubbish,
                # the captured lookbehind belongs to part_data
                callback(:part_data, lookbehind, 0, prev_index)
                @marks[:part_data] = i

                # Reconsider the current character as it might be the
                # beginning of a new sequence.
                i -= 1
              end

              i += 1
            when :end
              i += 1
            else
              return i;
          end
        end

        data_callback(:header_field, buffer, buffer_length)
        data_callback(:header_value, buffer, buffer_length)
        data_callback(:part_data, buffer, buffer_length)

        @index = index
        @state = state
        @flags = flags

        return buffer_length
      end

      private

      # Issues a callback.
      def callback(event, buffer = nil, start = nil, the_end = nil)
        return if !start.nil? && start == the_end
        if @callbacks.has_key? event
          @callbacks[event].call(buffer, start, the_end)
        end
      end

      # Issues a data callback,
      # The only valid options is :clear,
      # which, if true, will reset the appropriate mark to 0,
      # If not specified, the mark will be removed.
      def data_callback(data_type, buffer, the_end, options = {})
        return unless @marks.has_key? data_type
        callback(data_type, buffer, @marks[data_type], the_end)
        unless options[:clear]
          @marks[data_type] = 0
        else
          @marks.delete data_type
        end
      end
    end

    # A more high level interface to MultipartParser.
    class Reader

      # Initializes a MultipartReader, that will
      # read a request with the given boundary value.
      def initialize(boundary)
        @parser = Parser.new
        @parser.init_with_boundary(boundary)
        @header_field = ''
        @header_value = ''
        @part = nil
        @ended = false
        @on_error = nil
        @on_part = nil

        init_parser_callbacks
      end

      # Returns true if the parser has finished parsing
      def ended?
        @ended
      end

      # Sets to a code block to call
      # when part headers have been parsed.
      def on_part(&callback)
        @on_part = callback
      end

      # Sets a code block to call when
      # a parser error occurs.
      def on_error(&callback)
        @on_error = callback
      end

      # Write data from the given buffer (String)
      # into the reader.
      def write(buffer)
        bytes_parsed = @parser.write(buffer)
        if bytes_parsed != buffer.size
          msg = "Parser error, #{bytes_parsed} of #{buffer.length} bytes parsed"
          @on_error.call(msg) unless @on_error.nil?
        end
      end

      # Extracts a boundary value from a Content-Type header.
      # Note that it is the header value you provide here.
      # Raises NotMultipartError if content_type is invalid.
      def self.extract_boundary_value(content_type)
        if content_type =~ /multipart/i
          if match = (content_type =~ /boundary=(?:"([^"]+)"|([^;]+))/i)
            $1 || $2
          else
            raise NotMultipartError.new("No multipart boundary")
          end
        else
          raise NotMultipartError.new("Not a multipart content type!")
        end
      end

      class Part
        attr_accessor :filename, :headers, :name, :mime, :data, :ended

        def initialize
          @headers = {}
          @data_callback = nil
          @end_callback = nil
          @data = ''
          @ended = false
        end

        # Calls the data callback with the given data
        def emit_data(data)
          @data_callback.call(data) unless @data_callback.nil?
        end

        # Calls the end callback
        def emit_end
          @end_callback.call unless @end_callback.nil?
        end

        # Sets a block to be called when part data
        # is read. The block should take one parameter,
        # namely the read data.
        def on_data(&callback)
          @data_callback = callback
        end

        # Sets a block to be called when all data
        # for the part has been read.
        def on_end(&callback)
          @end_callback = callback
        end
      end

      private

      def init_parser_callbacks
        @parser.on(:part_begin) do
          @part = Part.new
          @header_field = ''
          @header_value = ''
        end

        @parser.on(:header_field) do |b, start, the_end|
          @header_field << b[start...the_end]
        end

        @parser.on(:header_value) do |b, start, the_end|
          @header_value << b[start...the_end]
        end

        @parser.on(:header_end) do
          @header_field.downcase!
          @part.headers[@header_field] = @header_value
          if @header_field == 'content-disposition'
            if @header_value =~ /name="([^"]+)"/i
              @part.name = $1
            end
            if @header_value =~ /filename="([^;]+)"/i
              match = $1
              start = (match.rindex("\\") || -1)+1
              @part.filename = match[start...(match.length)]
            end
          elsif @header_field == 'content-type'
            @part.mime = @header_value
          end
          @header_field = ''
          @header_value = ''
        end

        @parser.on(:headers_end) do
          @on_part.call(@part) unless @on_part.nil?
        end

        @parser.on(:part_data) do |b, start, the_end|
          @part.emit_data b[start...the_end]
        end

        @parser.on(:part_end) do
          @part.emit_end
        end

        @parser.on(:end) do
          @ended = true
        end
      end
    end

  end

end