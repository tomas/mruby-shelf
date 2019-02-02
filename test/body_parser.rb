# MIT License
#
# Copyright (c) Sebastian Katzer 2017
#
# Permission is hereby granted, free of charge, to any person obtaining a copy
# of this software and associated documentation files (the 'Software'), to deal
# in the Software without restriction, including without limitation the rights
# to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
# copies of the Software, and to permit persons to whom the Software is
# furnished to do so, subject to the following conditions:
#
# The above copyright notice and this permission notice shall be included in all
# copies or substantial portions of the Software.
#
# THE SOFTWARE IS PROVIDED 'AS IS', WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
# IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
# FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
# AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
# LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
# OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
# SOFTWARE.

class FakeInput
	attr_accessor :read
end

def env_for(path: '/', method: 'GET', query: '', body: '', type: Shelf::BodyParser::FORM_DATA_TYPE)
	input = FakeInput.new
	input.read = body
  { 'REQUEST_METHOD' => method, 
  	'PATH_INFO' => path, 
  	'QUERY_STRING' => query, 
  	'CONTENT_TYPE' => type, 
  	'rack.input' => input }
end

assert 'Shelf::BodyParser' do
  app = Shelf::Builder.app do
    use Shelf::BodyParser
    run -> (env) { 
    	[200, env[Shelf::SHELF_REQUEST_BODY_HASH], []] 
    }
  end

  _, params, = app.call(env_for(path: '/'))
  assert_kind_of Hash, params

  _, params, = app.call(env_for(body: 'id=2'))
  assert_equal nil, params[:id]
  assert_equal '2', params['id']

  _, params, = app.call(env_for(body: 'feed_id=5'))
  assert_equal '5', params['feed_id']

  _, params, = app.call(env_for(body: 'feed_id=5&age=99'))
  assert_equal '5',  params['feed_id']
  assert_equal '99', params['age']

  _, params, = app.call(env_for(body: 'feed_id=5&feed_id=6'))
  assert_equal %w[5 6], params['feed_id']

  _, params, = app.call(env_for(body: '{ "foo": 123 }'))
   assert_equal ["{ \"foo\": 123 }"],  params.keys # parsed as form data

  _, params, = app.call(env_for(body: '{ "foo" ', type: 'application/json'))
   assert_equal [],  params.keys # invalid

  _, params, = app.call(env_for(body: '{ "foo": 123 }', type: 'application/json')) # invalid type
  assert_equal 123,  params['foo']
end
