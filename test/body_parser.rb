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

def env_for(path: '/', method: 'GET', query: '', body: '', type: Shelf::BodyParser::FORM_DATA_TYPE, length: nil)
  { 'REQUEST_METHOD' => method, 
  	'PATH_INFO' => path, 
  	'QUERY_STRING' => query, 
  	'CONTENT_TYPE' => type, 
    'CONTENT_LENGTH' => length,
  	'rack.input' => body.nil? ? nil : InputStream.new(body) }
end

assert 'Shelf::BodyParser' do
  app = Shelf::Builder.app do
    use Shelf::BodyParser
    run -> (env) { 
    	[200, env[Shelf::SHELF_REQUEST_BODY_HASH]] 
    }
  end

  _, body, = app.call(env_for(path: '/'))
  assert_kind_of Hash, body
  assert_equal [], body.keys

  _, body, = app.call(env_for(path: '/', body: nil)) # no rack.input
  assert_kind_of Hash, body
  assert_equal [], body.keys

  _, body, = app.call(env_for(body: 'id=2'))
  assert_equal nil, body[:id]
  assert_equal '2', body['id']

  _, body, = app.call(env_for(body: 'feed_id=5'))
  assert_equal '5', body['feed_id']

  _, body, = app.call(env_for(body: 'feed_id=5&age=99'))
  assert_equal '5',  body['feed_id']
  assert_equal '99', body['age']

  _, body, = app.call(env_for(body: 'feed_id=5&feed_id=6'))
  assert_equal %w[5 6],body['feed_id']

  _, body, = app.call(env_for(body: '{ "foo": 123 }'))
   assert_equal ["{ \"foo\": 123 }"],  body.keys # parsed as form data

  _, body, = app.call(env_for(body: '{ "foo" ', type: 'application/json'))
   assert_equal [],  body.keys # invalid

  _, body, = app.call(env_for(body: '{ "foo": 123 }', type: 'application/json')) # invalid type
  assert_equal 123,  body['foo']

multipart_body =  ['--AaB03x',
  'content-disposition: form-data; name="field1"',
  '',
  "Joe Blow\r\nalmost tricked you!",
  '--AaB03x',
  'content-disposition: form-data; name="pics"; filename="file1.txt"',
  'Content-Type: text/plain',
  '',
  "... contents of file1.txt ...\r",
  '--AaB03x--',
  ''
].join("\r\n")

  multipart_type = 'multipart/form-data; boundary=AaB03x'
  _, body = app.call(env_for(body: multipart_body, length: multipart_body.bytesize, type: multipart_type))

  assert_equal body['field1'].data, "Joe Blow\r\nalmost tricked you!"
  assert_equal body['pics'].data, "... contents of file1.txt ...\r"

=begin
multipart_body = %{--AaB03x
Content-Disposition: form-data; name="foo"

bar
--AaB03x
Content-Disposition: form-data; name="files"
Content-Type: multipart/mixed, boundary=BbC04y

--BbC04y
Content-Disposition: attachment; filename="file.txt"
Content-Type: text/plain

contents
--BbC04y
Content-Disposition: attachment; filename="flowers.jpg"
Content-Type: image/jpeg
Content-Transfer-Encoding: binary

contents
--BbC04y--
--AaB03x--
}

  multipart_type = 'multipart/form-data; boundary=AaB03x'
  _, body = app.call(env_for(body: multipart_body, length: multipart_body.bytesize, type: multipart_type))
  assert_equal 123, body['foo']
=end
end
