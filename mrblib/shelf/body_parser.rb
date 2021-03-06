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

    def initialize(app)
      @app = app
    end

    def call(env)
      if env[SHELF_REQUEST_BODY_HASH].nil?
        env[SHELF_REQUEST_BODY_HASH] = env[RACK_INPUT].nil? ? {} : parse_body(env)
      end
      @app.call(env)
    end

    private

    def parse_body(env)
      stream = env[RACK_INPUT]
      case env[TYPE_HEADER]
      when JSON_TYPE
        parse_json(stream.read)
      when FORM_DATA_TYPE
        QueryParser.parse(stream.read)
      else
        {} # so we don't run this twice 
      end
    end

    def parse_json(str)
      JSON.parse(str)
    rescue JSON::ParserError
      {}
    end
  end
end
