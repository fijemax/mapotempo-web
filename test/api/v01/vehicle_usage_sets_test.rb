require 'test_helper'

class V01::VehicleUsageSetsTest < ActiveSupport::TestCase
  include Rack::Test::Methods
  include ActionDispatch::TestProcess

  def app
    Rails.application
  end

  setup do
    @customer = customers(:customer_one)
    @vehicle_usage_set = vehicle_usage_sets(:vehicle_usage_set_one)
  end

  def around
    Routers::RouterWrapper.stub_any_instance(:compute_batch, lambda { |url, mode, dimension, segments, options| segments.collect{ |i| [1000, 60, '_ibE_seK_seK_seK'] } } ) do
      yield
    end
  end

  def api(part = nil, param = {})
    part = part ? '/' + part.to_s : ''
    "/api/0.1/vehicle_usage_sets#{part}.json?api_key=testkey1&" + param.collect{ |k, v| "#{k}=" + URI.escape(v.to_s) }.join('&')
  end

  test 'should return customer''s vehicle_usage_sets' do
    get api()
    assert last_response.ok?, last_response.body
    assert_equal @vehicle_usage_set.customer.vehicle_usage_sets.size, JSON.parse(last_response.body).size
  end

  test 'should return customer''s vehicle_usage_sets by ids' do
    get api(nil, 'ids' => @vehicle_usage_set.id)
    assert last_response.ok?, last_response.body
    assert_equal 1, JSON.parse(last_response.body).size
    assert_equal @vehicle_usage_set.id, JSON.parse(last_response.body)[0]['id']
  end

  test 'should return a vehicle_usage_set' do
    get api(@vehicle_usage_set.id)
    assert last_response.ok?, last_response.body
    assert_equal @vehicle_usage_set.name, JSON.parse(last_response.body)['name']
  end

  test 'should create a vehicle_usage_set' do
    assert_difference('VehicleUsageSet.count', 1) do
      @vehicle_usage_set.name = 'new name'
      post api(), @vehicle_usage_set.attributes
      assert last_response.created?, last_response.body
    end
  end

  test 'should update a vehicle_usage_set' do
    @vehicle_usage_set.name = 'new name'
    put api(@vehicle_usage_set.id), name: 'riri'
    assert last_response.ok?, last_response.body

    get api(@vehicle_usage_set.id)
    assert last_response.ok?, last_response.body
    assert_equal 'riri', JSON.parse(last_response.body)['name']
  end

  test 'should update a vehicle_usage_set store with null value' do
    put api(@vehicle_usage_set.id), store_start_id: nil, store_stop_id: nil, store_rest_id: nil
    assert last_response.ok?, last_response.body

    get api(@vehicle_usage_set.id)
    assert last_response.ok?, last_response.body
    assert_nil JSON.parse(last_response.body)['store_start_id']
    assert_nil JSON.parse(last_response.body)['store_stop_id']
    assert_nil JSON.parse(last_response.body)['store_rest_id']
  end

  test 'should destroy a vehicle_usage_set' do
    assert_difference('VehicleUsageSet.count', -1) do
      delete api(@vehicle_usage_set.id)
      assert_equal 204, last_response.status, last_response.body
    end
  end

  test 'should destroy multiple vehicle_usage_sets' do
    assert_difference('VehicleUsageSet.count', -1) do
      delete api + "&ids=#{vehicle_usage_sets(:vehicle_usage_set_one).id}"
      assert_equal 204, last_response.status, last_response.body
    end
  end

  test 'should import vehicle usage set from csv without replacing vehicles' do
    assert_difference('VehicleUsageSet.count', 0) do
      put api(), replace_vehicles: false, file: fixture_file_upload('files/import_vehicle_usage_sets_one.csv', 'text/csv')
      assert last_response.ok?, last_response.body
      json = JSON.parse(last_response.body)

      assert_equal '001', json[0]['ref']
      assert_not_equal 'Véhicule 1', json[0]['name']
      assert_equal '08:00:00', json[0]['vehicle_usages'][0]['open']
      assert_nil json[0]['vehicle_usages'][0]['close']
    end
  end

  test 'should import vehicle usage set from csv and replace vehicles' do
    @customer.update_attribute(:enable_multi_vehicle_usage_sets, true)

    assert_difference('VehicleUsageSet.count', 1) do
      put api(), replace_vehicles: true, file: fixture_file_upload('files/import_vehicle_usage_sets_one.csv', 'text/csv')
      assert last_response.ok?, last_response.body
      json = JSON.parse(last_response.body)

      assert_equal 'Véhicule 1', json[0]['name']
      assert_equal 'vehicle1@mapotempo.com', json[0]['contact_email']
      assert_equal 10, json[0]['consumption']
      assert_equal '08:00:00', json[0]['vehicle_usages'][2]['open']
      assert_nil json[0]['vehicle_usages'][2]['close']

      assert_equal 'Véhicule 2', json[1]['name']
      assert_equal 'vehicle2@mapotempo.com', json[1]['contact_email']
      assert_equal 15, json[1]['consumption']
      assert_nil json[1]['vehicle_usages'][2]['open']
      assert_nil json[1]['vehicle_usages'][2]['close']

      assert_equal 57600, @customer.vehicle_usage_sets.last.close
    end
  end
end
