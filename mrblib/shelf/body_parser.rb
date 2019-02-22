# MIT License
#
# Copyright (c) Tomas Pollak 2019
#
# Permission is hereby granted, free of charge, to any person obtaining a copy
# of this software and associated documentation files (the "Software"), to deal
# in the Software without restriction, including without limitation the rights
# to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
# copies of the Software, and to permit persons to whom the Software is
# furnished to do so, subject to the following conditions:
#
# The above copyright notice and this permission notice shall be included in all
# copies or substantial portions of the Software.
#
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
# IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
# FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
# AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
# LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
# OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
# SOFTWARE.

module Shelf
  # Parse the query and put the params into the shelf.request.body_hash.
  class BodyParser

    TYPE_HEADER    = 'CONTENT_TYPE'.freeze # not Content-Type
    RACK_INPUT     = 'rack.input'.freeze
    JSON_TYPE      = 'application/json'.freeze
    FORM_DATA_TYPE = 'application/x-www-form-urlencoded'.freeze
    MULTIPART_TYPE = 'multipart/form-data'.freeze
    BOUNDARY_REGEX = /\Amultipart\/.*boundary=\"?([^\";,]+)\"?/i
    MAX_SIZE       = (1024 * 1024 * 100).freeze # 100 MB

    # allow being called directly
    def self.call(env, opts = {})
      if env[SHELF_REQUEST_BODY_HASH].nil?
        env[SHELF_REQUEST_BODY_HASH] = if env[RACK_INPUT].nil?
          {}
        else 
          opts[:async] ? parse_body_async(env, opts) : parse_body(env, opts)
        end
      end
    end

    def initialize(app, opts = {})
      @app, @opts = app, opts
    end

    def call(env)
      # initialize parser
      self.class.call(env, @opts)

      # call next handler
      status, headers, body = @app.call(env)

      # and remove files if any were created
      if env[SHELF_REQUEST_BODY_HASH].keys.any?
        files = env[SHELF_REQUEST_BODY_HASH].select { |key, obj| obj.respond_to?(:file) && obj.file }
        files.each { |key, obj| dispose_file(obj.file) }
      end

      [status, headers, body]
    end

    private

    def self.parse_body_async(env, opts = {})
      Hash.new do |hash, key|
        obj = parse_body(env, opts)
        hash.default_proc = Proc.new { |h,k| obj[k] }
        obj[key]
      end
    end

    def self.parse_body(env, opts = {})
      max_size = opts[:max_size] || MAX_SIZE
      stream = env[RACK_INPUT]

      case env[TYPE_HEADER]
      when JSON_TYPE
        parse_json(stream.read(max_size))
      when FORM_DATA_TYPE
        QueryParser.parse(stream.read(max_size))
      when /^#{MULTIPART_TYPE}/
        boundary = env[TYPE_HEADER][BOUNDARY_REGEX, 1]
        Multipart.parse(stream, boundary, max_size) if boundary
      end
    end

    def self.parse_json(str)
      JSON.parse(str)
    rescue JSON::ParserError
      {}
    end

    def self.dispose_file(file)
      File.unlink(file.path)
    rescue Errno::ENOENT, Errno::EPERM
      # 
    end
  end
end
