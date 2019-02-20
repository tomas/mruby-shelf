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
    BOUNDARY_REGEX = %r|\Amultipart/.*boundary=\"?([^\";,]+)\"?|i
    MAX_SIZE       = (1024 * 1024 * 100).freeze # 100 MB

    def initialize(app, opts = {})
      @app = app
      @max_size = opts[:max_size] || MAX_SIZE
    end

    def call(env)
      if env[SHELF_REQUEST_BODY_HASH].nil?
        env[SHELF_REQUEST_BODY_HASH] = env[RACK_INPUT].nil? ? {} : initialize_parser(env)
      end

      status, headers, body = @app.call(env)

      if env[SHELF_REQUEST_BODY_HASH].keys.any?
        files = env[SHELF_REQUEST_BODY_HASH].select { |key, obj| obj.respond_to?(:file) && obj.file }
        files.each { |key, obj| File.unlink(obj.file.path) }
      end

      [status, headers, body]
    end

    private

    def initialize_parser(env)
      Hash.new do |hash, key|
        obj = parse_body(env)
        hash.default_proc = Proc.new { |h,k| obj[k] }
        obj[key]
      end
    end

    def parse_body(env)
      stream = env[RACK_INPUT]
      case env[TYPE_HEADER]
      when JSON_TYPE
        parse_json(stream.read(@max_size))
      when FORM_DATA_TYPE
        QueryParser.parse(stream.read(@max_size))
      when /^#{MULTIPART_TYPE}/
        boundary = env[TYPE_HEADER][BOUNDARY_REGEX, 1]
        Multipart.parse(stream, boundary, @max_size) if boundary
      end
    end

    def parse_json(str)
      JSON.parse(str)
    rescue JSON::ParserError
      {}
    end
  end
end
