require 'helper'
require 'fluent/plugin/out_logentries_ssl.rb'

# rubocop:disable Metrics/ClassLength
class LogentriesSSLOutTest < Test::Unit::TestCase
  setup do
    Fluent::Test.setup
  end

  def setup
    Dir.mkdir('test/tmp')
  end

  def teardown
    Dir.glob('test/tmp/*').each { |f| File.unlink(f) }
    Dir.rmdir('test/tmp')
  end

  CONF = %(
          token_path test/tmp/tokens.yml
          max_retries 2
          verify_fqdn false
          ).freeze

  TOKENS = { 'app' => 'token', 'app2' => 'token2' }.freeze

  def write_tokens
    File.open('test/tmp/tokens.yml', 'w') do |f|
      f.write TOKENS.to_yaml.to_s
    end
  end

  def stub_socket
    socket = mock('tcpsocket')
    socket.stubs(:connect).returns(socket)
    socket.stubs(:sync_close=)
    socket.stubs(:close)
    OpenSSL::SSL::SSLSocket.expects(:new).at_least_once.with(any_parameters)
                           .returns(socket)
    socket
  end

  test 'configuration' do
    write_tokens
    d = create_driver(CONF)
    assert_equal 'test/tmp/tokens.yml', d.instance.token_path
    assert_equal 2, d.instance.max_retries
    assert_equal 443, d.instance.le_port
    assert_equal 'data.logentries.com', d.instance.le_host
  end

  test 'tags-tokens' do
    write_tokens
    d = create_driver(CONF)
    assert_equal 'token', d.instance.tag_token('app')
    assert_equal 'token2', d.instance.tag_token('app2')
    assert_equal nil, d.instance.tag_token('app3')
  end

  test 'using default token' do
    conf = %(
         default_token aaa-bbb-ccc
          max_retries 2
          verify_fqdn false
          )
    d = create_driver(conf)
    assert_equal 'aaa-bbb-ccc', d.instance.tag_token('app1')
    assert_equal 'aaa-bbb-ccc', d.instance.tag_token('app2')
  end

  test 'using default token with token file' do
    write_tokens
    conf = %(
          token_path test/tmp/tokens.yml
          default_token aaa-bbb-ccc
          max_retries 2
          verify_fqdn false
          )
    d = create_driver(conf)
    assert_equal 'token', d.instance.tag_token('app')
    assert_equal 'token2', d.instance.tag_token('app2')
    assert_equal 'aaa-bbb-ccc', d.instance.tag_token('app3')
  end

  test 'no token info' do
    assert_raise Fluent::ConfigError do
      create_driver('max_retries 2')
    end
  end

  test 'unreadable tokens' do
    assert_raise Fluent::ConfigError do
      create_driver(CONF)
    end
  end

  test 'sending to logentries' do
    write_tokens
    socket = stub_socket
    message = { 'message' => 'Hello' }
    socket.expects(:write)
          .with(regexp_matches(/^token {.*message.*Hello.*}\s+/i))
    d = create_driver(CONF)
    time = event_time('2017-01-01 13:37:00 UTC')
    d.run(default_tag: 'app') do
      d.feed(time, message)
    end
  end

  test 'retries on errors' do
    write_tokens
    socket = stub_socket
    message = { 'message' => 'Hello' }
    socket.expects(:write).with(anything).twice.raises(Errno::ECONNRESET)
          .then.returns('ok')
    d = create_driver(CONF)
    time = event_time('2017-01-01 13:37:00 UTC')
    d.run(default_tag: 'app') do
      d.feed(time, message)
    end
  end

  test 'sending too large events to LE' do
    write_tokens
    socket = stub_socket
    message = { 'hello' =>
                'a' *
                (Fluent::Plugin::LogentriesSSL::MessageHelper::MAX_SIZE + 100) }
    socket.expects(:write).with(anything).twice
    d = create_driver(CONF)
    time = event_time('2017-01-01 13:37:00 UTC')
    d.run(default_tag: 'app') do
      d.feed(time, message)
    end
  end

  private

  def create_driver(conf)
    Fluent::Test::Driver::Output
      .new(Fluent::Plugin::LogentriesSSL::Output).configure(conf)
  end
end
