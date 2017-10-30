require 'test_helper'

class V01::VisitsTest < ActiveSupport::TestCase
  include Rack::Test::Methods
  include ActionDispatch::TestProcess

  def app
    Rails.application
  end

  setup do
    @destination = destinations(:destination_one)
    @visit = visits(:visit_one)
  end

  def around
    Routers::RouterWrapper.stub_any_instance(:compute_batch, lambda { |url, mode, dimension, segments, options| segments.collect{ |i| [1000, 60, '_ibE_seK_seK_seK'] } } ) do
      yield
    end
  end

  def api(part = nil, param = {})
    part = part ? '/' + part.to_s : ''
    "/api/0.1/visits#{part}.json?api_key=testkey1&" + param.collect{ |k, v| "#{k}=#{v}" }.join('&')
  end

  def api_destination(destination_id, part = nil, param = {})
    part = part ? '/' + part.to_s : ''
    "/api/0.1/destinations/#{destination_id}/visits#{part}.json?api_key=testkey1&" + param.collect{ |k, v| "#{k}=#{v}" }.join('&')
  end

  test "should return destination's visits" do
    get api_destination(@destination.id)
    assert last_response.ok?, last_response.body
    assert_equal @destination.visits.size, JSON.parse(last_response.body).size
  end

  test "should return destination's visits by ids" do
    get api_destination(@destination.id, nil, 'ids' => @visit.id)
    assert last_response.ok?, last_response.body
    assert_equal 1, JSON.parse(last_response.body).size
    assert_equal @visit.id, JSON.parse(last_response.body)[0]['id']
  end

  test 'should return a visit' do
    get api_destination(@destination.id, @visit.id)
    assert last_response.ok?, last_response.body
    assert_equal @visit.ref, JSON.parse(last_response.body)['ref']
  end

  test 'should return a visit by ref' do
    get api_destination(@destination.id, "ref:#{@visit.ref}")
    assert last_response.ok?, last_response.body
    assert_equal @visit.ref, JSON.parse(last_response.body)['ref']
  end

  test 'should create a visit' do
    # tags can be a string separated by comma or an array
    [
      tags(:tag_one).id.to_s + ',' + tags(:tag_two).id.to_s,
      [tags(:tag_one).id, tags(:tag_two).id]
    ].each do |tags|
      assert_difference('Visit.count', 1) do
        assert_difference('Stop.count', 2) do
          post api_destination(@destination.id), @visit.attributes.merge({tag_ids: tags, 'quantities' => [{deliverable_unit_id: 1, quantity: 3.5}]}).except('id').to_json, 'CONTENT_TYPE' => 'application/json'

          assert last_response.created?, last_response.body
          visit = JSON.parse last_response.body
          assert_equal 2, visit['tag_ids'].size
          assert_equal 3.5, visit['quantities'][0]['quantity']
          assert_equal '10:00:00', visit['open']
          assert_equal '11:00:00', visit['close']
          assert_equal '10:00:00', visit['open1']
          assert_equal '11:00:00', visit['close1']
          assert_equal '00:05:33', visit['take_over']
          assert_equal '00:05:00', visit['take_over_default']
        end
      end
    end
  end

  test 'should create a visit with negative quantity' do
    # tags can be a string separated by comma or an array
    [
      tags(:tag_one).id.to_s + ',' + tags(:tag_two).id.to_s,
      [tags(:tag_one).id, tags(:tag_two).id]
    ].each do |tags|
      assert_difference('Visit.count', 1) do
        assert_difference('Stop.count', 2) do
          post api_destination(@destination.id), @visit.attributes.merge({tag_ids: tags, 'quantities' => [{deliverable_unit_id: 1, quantity: -3.5}]}).except('id').to_json, 'CONTENT_TYPE' => 'application/json'

          assert last_response.created?, last_response.body
          visit = JSON.parse last_response.body
          assert_equal 2, visit['tag_ids'].size
          assert_equal -3.5, visit['quantities'][0]['quantity']
          assert_equal '10:00:00', visit['open']
          assert_equal '11:00:00', visit['close']
          assert_equal '10:00:00', visit['open1']
          assert_equal '11:00:00', visit['close1']
          assert_equal '00:05:33', visit['take_over']
          assert_equal '00:05:00', visit['take_over_default']
        end
      end
    end
  end

  test 'should create a visit with none tag' do
    ['', nil, []].each do |tags|
      assert_difference('Visit.count', 1) do
        post api_destination(@destination.id), @visit.attributes.merge({tag_ids: tags, 'quantities' => nil}).except('id'), as: :json
        assert last_response.created?, last_response.body
      end
    end
  end

  test 'should not create a visit' do
    post api_destination(@destination.id), @visit.attributes.merge(tag_ids: [tags(:tag_three).id], 'quantities' => nil).except('id'), as: :json
    assert_equal 400, last_response.status, last_response.body
  end

  test 'should update a visit' do
    [
      tags(:tag_one).id.to_s + ',' + tags(:tag_two).id.to_s,
      [tags(:tag_one).id, tags(:tag_two).id],
      '',
      nil,
      []
    ].each do |tags|
      put api_destination(@destination.id, @visit.id), @visit.attributes.merge({tag_ids: tags, 'quantities' => [{deliverable_unit_id: 1, quantity: 3.5}, {deliverable_unit_id: 2, quantity: 3.5}]}).to_json, 'CONTENT_TYPE' => 'application/json'
      assert last_response.ok?, last_response.body

      get api_destination(@destination.id, @visit.id)
      assert last_response.ok?, last_response.body
      visit = JSON.parse last_response.body
      assert_equal @visit.ref, visit['ref']
      assert_equal [3.5, 3.5], visit['quantities'].map{ |q| q['quantity'] }
    end
  end

  test 'should update a visit with quantities or return parse error' do


    put api_destination(@destination.id, @visit.id), { quantities: [{ deliverable_unit_id: 1, quantity: 10 }] }.to_json, 'CONTENT_TYPE' => 'application/json'
    assert last_response.ok?, last_response.body

    visit = JSON.parse(last_response.body)
    assert visit['quantities'][0]['deliverable_unit_id'], 1
    assert visit['quantities'][0]['quantity'], 10

    put api_destination(@destination.id, @visit.id), { quantities: [{ deliverable_unit_id: 1, quantity: -10 }] }.to_json, 'CONTENT_TYPE' => 'application/json'
    assert last_response.ok?, last_response.body

    visit = JSON.parse(last_response.body)
    assert visit['quantities'][0]['deliverable_unit_id'], 1
    assert visit['quantities'][0]['quantity'], -10

    put api_destination(@destination.id, @visit.id), { quantities: [{ deliverable_unit: 1, quantity: 'aaa' }] }.to_json, 'CONTENT_TYPE' => 'application/json'
    assert last_response.bad_request?
    response = JSON.parse(last_response.body)
    assert_equal response['message'], 'quantities[0][deliverable_unit_id] is missing, quantities[0][quantity] is invalid'
  end

  test 'should destroy a visit' do
    assert_difference('Visit.count', -1) do
      delete api_destination(@destination.id, @visit.id)
      assert_equal 204, last_response.status, last_response.body
    end
  end

  test "should return customer's visits" do
    get api()
    assert last_response.ok?, last_response.body
    assert_equal @destination.customer.visits.size, JSON.parse(last_response.body).size
  end

  test 'should return customer''s visits geojson' do
    get api.gsub('.json', '.geojson') + '&quantities=true'
    assert last_response.ok?, last_response.body
    features = JSON.parse(last_response.body)['features']
    assert_equal @destination.customer.visits.size, features.size
    features.each{ |feat|
      assert feat['properties']['quantities'].size > 0
    }
  end

  test 'should return specific visits' do
    get api(nil, ids: "ref:#{visits(:visit_one).ref},#{visits(:visit_two).id}")
    assert last_response.ok?, last_response.body
    assert_equal 2, JSON.parse(last_response.body).size
  end

  test 'should destroy multiple destinations' do
    assert_difference('Visit.count', -2) do
      delete api + "&ids=#{visits(:visit_one).id},#{visits(:visit_two).id}"
      assert_equal 204, last_response.status, last_response.body
    end
  end
end
