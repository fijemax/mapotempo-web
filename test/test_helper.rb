if (!ENV.key?('COV') && !ENV.key?('COVERAGE')) || (ENV['COV'] != 'false' && ENV['COVERAGE'] != 'false')
  require 'simplecov'
  SimpleCov.minimum_coverage 84
  SimpleCov.start 'rails'
end

ENV['RAILS_ENV'] ||= 'test'
require File.expand_path('../../config/environment', __FILE__)
require 'rails/test_help'
require 'webmock/minitest'

Dir[Rails.root.join('lib/**/*.rb')].each { |file| load file } # only explicitly required files are tracked

WebMock.allow_net_connect!
# WebMock.disable_net_connect!

require 'html_validation'
#PageValidations::HTMLValidation.show_warnings = false

class ActiveSupport::TestCase
  ActiveRecord::Migration.check_pending!

  # Setup all fixtures in test/fixtures/*.yml for all tests in alphabetical order.
  #
  # Note: You'll currently still have to declare fixtures explicitly in integration tests
  # -- they do not yet inherit this setting
  fixtures :all

  # Add more helper methods to be used by all tests here...
  # Associate delayed job class to customer
  set_fixture_class delayed_jobs: Delayed::Backend::ActiveRecord::Job

  def setup
    uri_template = Addressable::Template.new('gpp3-wxs.ign.fr/{api_key}/geoportail/ols')
    @stub_GeocodeRequest = stub_request(:post, uri_template).with { |request|
      request.body.include?("methodName='GeocodeRequest'")
    }.to_return(File.new(File.expand_path('../', __FILE__) + '/fixtures/gpp3-wxs.ign.fr/GeocodeRequest.xml').read)

    uri_template = Addressable::Template.new('gpp3-wxs.ign.fr/{api_key}/geoportail/ols')
    @stub_LocationUtilityService = stub_request(:post, uri_template).with { |request|
      request.body.include?("methodName='LocationUtilityService'")
    }.to_return(File.new(File.expand_path('../', __FILE__) + '/fixtures/gpp3-wxs.ign.fr/LocationUtilityService.xml').read)

    @stub_GeocodeMapotempo = stub_request(:get, 'https://geocode.mapotempo.com/0.1/geocode.json').with(:query => hash_including({})).
      to_return(File.new(File.expand_path('../', __FILE__) + '/fixtures/geocode.mapotempo.com/geocode.json').read)

    def (Mapotempo::Application.config.geocode_geocoder).code_bulk(addresses)
      addresses.map{ |a| {lat: 1, lng: 1, quality: 'street', accuracy: 0.9} }
    end
  end

  def teardown
    remove_request_stub(@stub_GeocodeRequest)
    remove_request_stub(@stub_LocationUtilityService)
    remove_request_stub(@stub_GeocodeMapotempo)
  end

  def assert_valid(response)
#    html_validation = PageValidations::HTMLValidation.new
#    validation = html_validation.validation(response.body, response.to_s)
#    assert validation.valid?, validation.exceptions
  end
end

class ActionController::TestCase
  include Devise::Test::ControllerHelpers
end

def suppress_output
  begin
    original_stderr = $stderr.clone
    original_stdout = $stdout.clone
    $stderr.reopen(File.new('/dev/null', 'w'))
    $stdout.reopen(File.new('/dev/null', 'w'))
    retval = yield
  rescue Exception => e
    $stdout.reopen(original_stdout)
    $stderr.reopen(original_stderr)
    raise e
  ensure
    $stdout.reopen(original_stdout)
    $stderr.reopen(original_stderr)
  end
  retval
end
