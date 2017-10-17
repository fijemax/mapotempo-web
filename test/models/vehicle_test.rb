require 'test_helper'

class VehicleTest < ActiveSupport::TestCase

  def around
    Routers::RouterWrapper.stub_any_instance(:compute_batch, lambda { |_url, _mode, _dimension, segments, _options| segments.collect{ |_i| [1, 1, '_ibE_seK_seK_seK'] } } ) do
      yield
    end
  end

  test 'should not save' do
    vehicle = customers(:customer_one).vehicles.build
    assert_not vehicle.save, 'Saved without required fields'
  end

  test 'should not save speed_multiplicator' do
    vehicle = customers(:customer_one).vehicles.build(name: 'plop', speed_multiplicator: 2)
    assert_not vehicle.save
  end

  test 'should save' do
    vehicle = customers(:customer_one).vehicles.build(name: '1')
    vehicle.save!
  end

  test 'should set hash router options' do
    vehicle = customers(:customer_one).vehicles.build(name: '2')
    vehicle.router_options = {
        time: true,
        distance: true,
        isochrone: true,
        isodistance: true,
        avoid_zones: true,
        track: true,
        motorway: true,
        toll: true,
        trailers: 2,
        weight: 10,
        weight_per_axle: 5,
        height: 5,
        width: 6,
        length: 30,
        hazardous_goods: 'gas',
        max_walk_distance: 200,
        approach: 'curb',
        snap: 50,
        strict_restriction: false
    }

    vehicle.save!

    assert_equal vehicle.time, true
    assert_equal vehicle.time?, true

    assert_equal vehicle.distance, true
    assert_equal vehicle.distance?, true

    assert_equal vehicle.isochrone, true
    assert_equal vehicle.isochrone?, true

    assert_equal vehicle.isodistance, true
    assert_equal vehicle.isodistance?, true

    assert_equal vehicle.avoid_zones, true
    assert_equal vehicle.avoid_zones?, true

    assert_equal vehicle.track, true
    assert_equal vehicle.track?, true

    assert_equal vehicle.motorway, true
    assert_equal vehicle.motorway?, true

    assert_equal vehicle.toll, true
    assert_equal vehicle.toll?, true

    assert_equal vehicle.trailers, '2'
    assert_equal vehicle.weight, '10'
    assert_equal vehicle.weight_per_axle, '5'
    assert_equal vehicle.height, '5'
    assert_equal vehicle.width, '6'
    assert_equal vehicle.length, '30'
    assert_equal vehicle.hazardous_goods, 'gas'
    assert_equal vehicle.max_walk_distance, '200'
    assert_equal vehicle.approach, 'curb'
    assert_equal vehicle.snap, '50'
    assert_equal vehicle.strict_restriction, false
  end

  test 'should use default router options' do
    customer = customers(:customer_two)
    customer.router_options = {
        motorway: true,
        trailers: 2,
        weight: 10,
        max_walk_distance: 200
    }

    vehicle = customer.vehicles.build(name: '3')
    vehicle.router_options = {
        motorway: false,
        weight_per_axle: 3,
        length: 30,
        hazardous_goods: 'gas'
    }
    vehicle.save!

    assert_equal vehicle.default_router_options['motorway'], 'false'
    assert_equal vehicle.default_router_options['trailers'], '2'
    assert_equal vehicle.default_router_options['weight'], '10'
    assert_equal vehicle.default_router_options['weight_per_axle'], '3'
    assert_equal vehicle.default_router_options['length'], '30'
    assert_equal vehicle.default_router_options['hazardous_goods'], 'gas'
    assert_equal vehicle.default_router_options['max_walk_distance'], '200'
  end

  test 'should return error if capacity is invalid' do
    vehicle = vehicles(:vehicle_one)

    vehicle.capacities = {customers(:customer_one).deliverable_units[0].id => '12,3'}
    assert vehicle.save

    vehicle.capacities = {customers(:customer_one).deliverable_units[0].id => 'not a float'}
    assert_not vehicle.save
    assert_equal vehicle.errors.first.second, I18n.t('activerecord.errors.models.vehicle.attributes.capacities.not_float')
  end

  test 'should update outdated for capacity' do
    vehicle = vehicles(:vehicle_one)
    assert_not vehicle.vehicle_usages[0].routes[-1].outdated
    vehicle.capacities = {customers(:customer_one).deliverable_units[0].id => '12,3'}
    vehicle.save!
    vehicle.reload
    assert vehicle.vehicle_usages[0].routes[-1].outdated
    assert_equal 12.3, Vehicle.where(name: :vehicle_one).first.capacities[customers(:customer_one).deliverable_units[0].id]
  end

  test 'should update outdated for empty capacity' do
    vehicle = vehicles(:vehicle_one)
    assert_not vehicle.vehicle_usages[0].routes[-1].outdated
    vehicle.capacities = {}
    vehicle.save!
    vehicle.reload
    assert vehicle.vehicle_usages[0].routes[-1].outdated
    assert_nil Vehicle.where(name: :vehicle_one).first.capacities[customers(:customer_one).deliverable_units[0].id]
  end

  test 'should not accept negative value for capacity' do
    vehicle = vehicles(:vehicle_one)
    assert_not vehicle.vehicle_usages[0].routes[-1].outdated
    vehicle.capacities = {customers(:customer_one).deliverable_units[0].id => '-12,3'}
    assert !vehicle.save
  end

  test 'should update geojson if color changed' do
    vehicle = vehicles(:vehicle_one)
    vehicle.color = '#123123' # Some visits are tagged with #FF0000
    vehicle.save!
    vehicle.reload
    o = vehicle.vehicle_usages[0].routes[-1]
    features = JSON.parse('[' + ((o.geojson_tracks || []) + (o.geojson_points || [])).join(',') + ']')
    assert_equal ['#123123', '#FF0000'], features.map{ |f| f['properties']['color'] }.uniq.compact
  end

  test 'should validate email' do
    vehicle = vehicles(:vehicle_one)
    assert vehicle.valid?
    assert vehicle.update! contact_email: ''
    assert vehicle.contact_email.nil?
    assert vehicle.valid?
  end
end
