require 'test_helper'
require 'routers/router_wrapper'

class D < Struct.new(:lat, :lng, :id, :open1, :close1, :open2, :close2, :duration, :vehicle_usage)
  def visit
    self
  end
  def default_quantities?
    false
  end
  def route
    Struct.new(:vehicle_usage, :vehicle_usage_id).new(vehicle_usage, vehicle_usage.try(&:id))
  end
end

class PlanningTest < ActiveSupport::TestCase

  def around
    Routers::RouterWrapper.stub_any_instance(:compute_batch, lambda { |url, mode, dimension, segments, options| segments.collect{ |i| [1, 1, '_ibE_seK_seK_seK'] } } ) do
      Routers::RouterWrapper.stub_any_instance(:matrix, lambda{ |url, mode, dimensions, row, column, options| [Array.new(row.size) { Array.new(column.size, 0) }] }) do
        yield
      end
    end
  end

  # default order, rest at the end
  def optimizer_route(positions, services, vehicles)
    [[]] + [(services + vehicles[0][:rests]).collect{ |s| s[:stop_id] }]
  end

  # return all services in reverse order in first route, rests at the end
  def optimizer_global(positions, services, vehicles)
    [[]] + vehicles.each_with_index.map{ |v, i|
      ((i.zero? ? services.reject{ |s| s[:vehicle_id] } : []) + services.select{ |s| s[:vehicle_id] && s[:vehicle_id] == v[:id] } + v[:rests]).map{ |s|
        s[:stop_id]
      }.reverse
    }
  end

  test 'should not save' do
    planning = Planning.new
    assert_not planning.save, 'Saved without required fields'
  end

  test 'should not save with inconsistent attributes' do
    {
      vehicle_usage_set: vehicle_usage_sets(:vehicle_usage_set_two),
      zonings: [zonings(:zoning_three)]
    }.each{ |k, v|
      attr = {name: 'plop'}
      attr[k] = v
      planning = customers(:customer_one).plannings.build(attr)
      assert_not planning.save, 'Saved with inconsistent attributes'
    }
  end

  test 'should save' do
    planning = customers(:customer_one).plannings.build(name: 'plop', vehicle_usage_set: vehicle_usage_sets(:vehicle_usage_set_one), zonings: [zonings(:zoning_one)])
    planning.default_routes
    planning.save!
  end

  test 'should save according to tag operation' do
    planning_and_tags = customers(:customer_two).plannings.build(name: 'plop', vehicle_usage_set: vehicle_usage_sets(:vehicle_usage_set_two), zonings: [zonings(:zoning_three)], tag_operation: 'and', tag_ids: [tags(:tag_three).id, tags(:tag_four).id])
    planning_and_tags.default_routes
    planning_and_tags.save!
    assert_equal 1, planning_and_tags.visits_compatibles.count

    planning_or_tags = customers(:customer_two).plannings.build(name: 'plop 2', vehicle_usage_set: vehicle_usage_sets(:vehicle_usage_set_two), zonings: [zonings(:zoning_three)], tag_operation: 'or', tag_ids: [tags(:tag_three).id, tags(:tag_four).id])
    planning_or_tags.default_routes
    planning_or_tags.save!
    assert_equal 2, planning_or_tags.visits_compatibles.count
  end

  test 'should not loading stops after save import' do
    # Without zonings
    planning = customers(:customer_one).plannings.build(name: 'plop', vehicle_usage_set: vehicle_usage_sets(:vehicle_usage_set_one))
    planning.default_routes
    planning.compute
    Planning.import([planning], recursive: true, validate: false)

    begin
      Stop.class_eval do
        after_initialize :after_init
        def after_init
          raise
        end
      end

      t, z = planning.tags, planning.zonings
      planning.reload
      planning.tags, planning.zonings = t, z
      planning.routes.each { |route| route.complete_geojson }
      planning.save!

    ensure
      Stop.class_eval do
        def after_init
        end
      end
    end
  end

  test 'should dup' do
    planning = plannings(:planning_one)
    planning_dup = planning.duplicate

    assert_equal planning_dup, planning_dup.routes[0].planning
    planning_dup.save!
    planning_dup.routes.each{ |r|
      assert_not r.outdated
    }
  end

  test 'should set_routes' do
    planning = plannings(:planning_one)

    planning.set_routes({'abc' => {visits: [[visits(:visit_one)]]}})
    assert planning.routes[1].stops.select{ |stop| stop.is_a?(StopVisit) }.collect(&:visit).include?(visits(:visit_one))
    planning.save!
  end

  test 'should not set_routes for tags' do
    planning = plannings(:planning_one)
    planning.tags << tags(:tag_two)

    planning.set_routes({'abc' => {visits: [[visits(:visit_one)]]}})
    assert_not planning.routes[1].stops.select{ |stop| stop.is_a?(StopVisit) }.collect(&:visit).include?(visits(:visit_one))
    planning.save!
  end

  test 'should set_routes with ref_vehicle' do
    planning = plannings(:planning_one)

    planning.set_routes({'abc' => {visits: [[visits(:visit_one)]], ref_vehicle: vehicles(:vehicle_three).ref}})
    assert planning.routes.find{ |r| r.vehicle_usage.try(&:vehicle) == vehicles(:vehicle_three) }.stops.select{ |stop| stop.is_a?(StopVisit) }.collect(&:visit).include?(visits(:visit_one))
    planning.save!
  end

  test 'should not set_routes for size' do
    planning = plannings(:planning_one)

    assert_raises(RuntimeError) {
      planning.set_routes(Hash[0.upto(planning.routes.size).collect{ |i| ["route#{i}", {visits: [visits(:visit_one)]}] }])
    }
    planning.save!
  end

  test 'should vehicle_usage_add' do
    planning = plannings(:planning_one)
    assert_difference('Stop.count', 1) do # One StopRest
      assert_difference('Route.count', 1) do
        planning.vehicle_usage_add(vehicle_usages(:vehicle_usage_one_three))
        planning.save!
      end
    end
  end

  test 'should vehicle_usage_remove' do
    planning = plannings(:planning_one)
    assert_difference('Stop.count', -1) do
      assert_difference('Route.count', -1) do
        planning.vehicle_usage_remove(vehicle_usages(:vehicle_usage_one_one))
        planning.save!
      end
    end
  end

  test 'should visit_add' do
    planning = plannings(:planning_one)
    assert_difference('Stop.count') do
      planning.visit_add(visits(:visit_two))
      planning.save!
    end
  end

  test 'should visit_remove' do
    planning = plannings(:planning_one)
    assert_difference('Stop.count', -2) do
      planning.visit_remove(visits(:visit_one))
      planning.save!
    end
  end

  test 'move stop on same route from inside to start' do
    planning = plannings(:planning_one)
    r = planning.routes.select{ |route| route == routes(:route_one_one) }.first
    s = r.stops[1]
    assert_equal 2, s.index
    assert_difference('Stop.count', 0) do
      planning.move_stop(r, s, 1)
      planning.save!
      s.reload
      assert_equal 1, s.index
    end
  end

  test 'move stop on same route from inside to end' do
    planning = plannings(:planning_one)
    r = planning.routes.select{ |route| route == routes(:route_one_one) }.first
    s = r.stops[1]
    assert_equal 2, s.index
    assert_difference('Stop.count', 0) do
      planning.move_stop(r, s, 3)
      planning.save!
      s.reload
      assert_equal 3, s.index
    end
  end

  test 'move stop on same route from start to inside' do
    planning = plannings(:planning_one)
    r = planning.routes.select{ |route| route == routes(:route_one_one) }.first
    s = r.stops[0]
    assert_equal 1, s.index
    assert_difference('Stop.count', 0) do
      planning.move_stop(r, s, 2)
      planning.save!
      s.reload
      assert_equal 2, s.index
    end
  end

  test 'move stop on same route from end to inside' do
    o = plannings(:planning_one)
    r = o.routes.select{ |route| route == routes(:route_one_one) }.first
    s = r.stops[2]
    assert_equal 3,  s.index
    assert_difference('Stop.count', 0) do
      o.move_stop(r, s, 2)
      o.save!
      s.reload
      assert_equal 2, s.index
    end
  end

  test 'move stop from unaffected to affected route' do
    o = plannings(:planning_one)
    s = o.routes.select{ |route| route == routes(:route_zero_one) }.first.stops[0]
    assert s.index
    r = o.routes.select{ |route| route == routes(:route_one_one) }.first
    assert_difference('Stop.count', 0) do
      assert_difference('r.stops.size', 1) do
        o.move_stop(r, s, 1)
        o.save!
      end
    end
  end

  test 'move stop from unaffected to affected route with automatic_insert' do
    o = plannings(:planning_one)
    s = o.routes.select{ |route| route == routes(:route_zero_one) }.first.stops[0]
    assert s.index
    r = o.routes.select{ |route| route == routes(:route_one_one) }.first
    assert_difference('Stop.count', 0) do
      assert_difference('r.stops.size', 1) do
        o.move_stop(r, s, nil)
        o.save!
      end
    end
  end

  test 'move stop from affected to affected route' do
    o = plannings(:planning_one)
    s = o.routes.select{ |route| route == routes(:route_one_one) }.first.stops[0]
    assert s.index
    r = o.routes.select{ |route| route == routes(:route_three_one) }.first
    assert_difference('Stop.count', 0) do
      assert_difference('r.stops.size', 1) do
        o.move_stop(r, s, 1)
        o.save!
      end
    end
  end

  test 'move stop to unaffected route' do
    o = plannings(:planning_one)
    s = o.routes.select{ |route| route == routes(:route_one_one) }.first.stops[1]
    assert s.index
    r = o.routes.select{ |route| route == routes(:route_zero_one) }.first
    assert_difference('Stop.count', 0) do
      assert_difference('r.stops.size', 1) do
        o.move_stop(r, s, 1)
        o.save!
      end
    end
  end

  test 'should compute' do
    o = plannings(:planning_one)
    assert_no_difference('Stop.count') do
      o.zoning_outdated = true
      o.compute
      o.routes.select{ |r| r.vehicle_usage }.each{ |r|
        assert_not r.outdated
      }
      assert_not o.zoning_outdated
      o.save!
    end
  end

  test 'should compute with non geocoded' do
    o = plannings(:planning_one)
    o.zoning_outdated = true
    d0 = o.routes[0].stops[0].visit.destination
    d0.lat = d0.lng = nil
    o.compute
    o.routes.select{ |r| r.vehicle_usage }.each{ |r|
      assert_not r.outdated
    }
    assert_not o.zoning_outdated
  end

  test 'should outdated' do
    o = plannings(:planning_one)
    assert_not o.outdated

    o.routes[1].outdated = true
    assert o.outdated
  end

  test 'should update zoning' do
    o = plannings(:planning_one)
    assert_not o.zoning_outdated
    o.zonings = [zonings(:zoning_two)]
    o.save!
    assert_not o.outdated
  end

  test 'should automatic insert' do
    planning = plannings(:planning_one)
    stops_count = planning.routes.collect{ |r| r.stops.size }.inject(:+)
    planning.zonings = []
    assert_difference('Stop.count', 0) do
      # route_zero has not any vehicle_usage => stop will be affected to another route
      planning.automatic_insert(planning.routes.find{ |r| !r.vehicle_usage }.stops[0])
      planning.save!
    end
    planning.reload
    assert_equal 3, planning.routes.size
    assert_equal 0, planning.routes.find{ |r| !r.vehicle_usage }.stops.size
    assert_equal stops_count, planning.routes.select{ |r| r.vehicle_usage }.collect{ |r| r.stops.size }.inject(:+)
  end

  test 'should apply orders' do
    o = plannings(:planning_one)
    r = o.routes.find{ |ro| ro.ref == 'route_one' }
    assert r.stops[0].active
    assert r.stops[1].active

    oa = order_arrays(:order_array_one)
    o.apply_orders(oa, 0)
    assert r.stops[0].active
    assert_not r.stops[1].active
    o.save!
  end

  test 'should apply orders and destroy' do
    o = plannings(:planning_one)
    oa = order_arrays(:order_array_one)
    o.apply_orders(oa, 0)
    o.save!
    oa.destroy
    o.save!
  end

  test 'plan with service time' do
    v = vehicle_usages(:vehicle_usage_one_one)
    r = v.routes.take

    # 1st computation, set Stop times
    r.outdated = true
    r.compute
    stop_times = r.stops.map &:time
    route_start = r.start
    route_end = r.end

    # Add Service Time
    v.vehicle_usage_set.update!(
      service_time_start: 10.minutes.to_i,
      service_time_end: 25.minutes.to_i
    )

    # 2nd computation
    r.outdated = true
    r.compute
    stop_times2 = r.stops.map &:time
    route_start2 = r.start
    route_end2 = r.end

    # Make sure time has been added to route start and end, and stops are still in tw
    assert_equal route_start - 10.minutes.to_i, route_start2
    assert_equal stop_times[0], stop_times2[0]
    assert_equal route_end + 25.minutes.to_i, route_end2

    # Vehicle Usage overrides Service Time values
    v.update!(
      service_time_start: 50.minutes.to_i,
      service_time_end: 20.minutes.to_i
    )

    # 3rd computation
    r.outdated = true
    r.compute
    stop_times3 = r.stops.map &:time
    route_start3 = r.start
    route_end3 = r.end

    # Let's verify route start is minimal, stops are not at same time
    assert_equal Time.parse('10:00:00').seconds_since_midnight.to_i, route_start3
    assert_not_equal stop_times[0], stop_times3[0]
    assert_equal route_end + 20.minutes.to_i, route_end3

    # First stop should not be out of time window
    assert !r.stops[0].out_of_window

    # Change time window
    r.stops[0].visit.update!(
      open1: v.service_time_start + 5.minutes.to_i,
      close1: v.service_time_start + 10.minutes.to_i
    )

    # Compute a last time, this stop should be out of time window
    r.outdated = true
    r.compute
    assert r.stops[0].out_of_window
  end

  test 'plan using stores without lat or lng' do
    v = vehicle_usages(:vehicle_usage_one_one)
    r = v.routes.take
    r.planning.customer.stores.update_all lat: nil, lng: nil
    r.outdated = true
    r.compute
    r.stops.sort_by(&:index).each_with_index do |stop, index|
      if index.zero?
        # Can't trace path, store has no lat / lng to start with
        assert_equal 0, stop.distance
        assert_equal Time.parse('10:44:25').seconds_since_midnight.to_i, stop.time
      elsif index == r.stops.length - 1
        assert stop.distance.nil?
      else
        assert_equal 1.0, stop.distance
      end
    end
  end

  test 'validates format of REF field with invalid characters' do
    planning = plannings :planning_one
    assert_raises(ActiveRecord::RecordInvalid) do
      planning.update! ref: "test.abcd"
    end

    assert_equal ["ne doit pas contenir les caractères \".\", \"\\\" ou \"/\""], planning.errors[:ref]
  end

  test 'validates format of REF field with valid characters' do
    planning = plannings :planning_one
    assert planning.update! ref: "testabcd!@\#{$%^&*()_+},;'\"`[]|{}:<>?-=~"
  end

  test 'validates format of REF field with spaces' do
    planning = plannings :planning_one
    assert planning.update! ref: "  test abcd   "
    assert_equal "test abcd", planning.ref
  end

  test 'date format' do
    orig_locale = I18n.locale
    begin
      planning = plannings :planning_one
      planning.update! date: Date.new(2017, 1, 31)
      I18n.locale = :en
      assert_equal '01-31-2017', I18n.l(planning.date.to_time, format: :datepicker)
      I18n.locale = :fr
      assert_equal '31-01-2017', I18n.l(planning.date.to_time, format: :datepicker)
    ensure
      I18n.locale = orig_locale
    end
  end

  test 'duplicate should not change zonings outdated flag when initially false' do
    planning = plannings :planning_one
    assert !planning.zoning_outdated
    dup_planning = planning.duplicate
    dup_planning.save!
    assert !dup_planning.zoning_outdated
  end

  test 'duplicate should not change zonings outdated flag when initially true' do
    planning = plannings :planning_one
    planning.update! zoning_outdated: true
    assert planning.zoning_outdated
    dup_planning = planning.duplicate
    dup_planning.save!
    assert dup_planning.zoning_outdated
  end

  test 'should no amalgamate point at same position' do
    o = routes(:route_one_one)

    positions = [D.new(1,1,1), D.new(2,2,2), D.new(3,3,3)]
    ret = o.planning.send(:amalgamate_stops_same_position, positions, false) { |positions|
      assert_equal 3, positions.size
      pos = positions.sort
      [pos.collect{ |p|
        p[2]
      }]
    }
    assert_equal positions.size, ret[0].size
    assert_equal 1.upto(positions.size).to_a, ret[0]
  end

  test 'should amalgamate point at same position' do
    route = routes(:route_one_one)

    positions = [D.new(1,1,1,nil,nil,nil,nil,0), D.new(2,2,2,nil,nil,nil,nil,0), D.new(2,2,3,nil,nil,nil,nil,0), D.new(3,3,4,nil,nil,nil,nil,0)]
    ret = route.planning.send(:amalgamate_stops_same_position, positions, false) { |positions|
      assert_equal 3, positions.size
      pos = positions.sort
      [pos.collect{ |p|
        p[2]
      }]
    }
    assert_equal positions.size, ret[0].size
    assert_equal 1.upto(positions.size).to_a, ret[0]
  end

  test 'should no amalgamate point at same position, tw' do
    route = routes(:route_one_one)

    positions = [D.new(1,1,1,nil,nil,nil,nil,0), D.new(2,2,2,nil,nil,nil,nil,0), D.new(2,2,3,10,20,nil,nil,0), D.new(3,3,4,nil,nil,nil,nil,0)]
    ret = route.planning.send(:amalgamate_stops_same_position, positions, false) { |positions|
      assert_equal 4, positions.size
      [(1..(positions.size)).to_a]
    }
    assert_equal positions.size, ret[0].size
    assert_equal 1.upto(positions.size).to_a, ret[0]
  end

  test 'should optimize one route with one store rest' do
    route = routes(:route_one_one)
    optim = route.planning.optimize([route], false) { |*a|
      optimizer_route(*a)
    }
    assert_equal [route.stops.collect(&:id)], optim
  end

  test 'should optimize one route with one no-geoloc rest' do
    o = routes(:route_one_one)
    vehicle_usages(:vehicle_usage_one_one).update! store_rest: nil
    vehicle_usage_sets(:vehicle_usage_set_one).update! store_rest: nil
    o.reload
    optim = o.planning.optimize([o], false) { |*a|
      optimizer_route(*a)
    }
    assert_equal [o.stops.collect(&:id)], optim
  end

  test 'should optimize one route without any store' do
    o = routes(:route_one_one)
    vehicle_usages(:vehicle_usage_one_one).update! store_start: nil, store_stop: nil, store_rest: nil
    vehicle_usage_sets(:vehicle_usage_set_one).update! store_start: nil, store_stop: nil, store_rest: nil
    o.reload
    optim = o.planning.optimize([o], false) { |*a|
      optimizer_route(*a)
    }
    assert_equal [o.stops.collect(&:id)], optim
  end

  test 'should optimize one route with none geoloc store' do
    o = routes(:route_three_one)
    optim = o.planning.optimize([o], false) { |*a|
      optimizer_route(*a)
    }
    assert_equal [o.stops.collect(&:id)], optim
  end

  test 'should optimize global planning' do
    o = plannings(:planning_one)
    optim = o.optimize(o.routes, true) { |*a|
      optimizer_global(*a)
    }
    assert_equal 0, optim[0].size
    assert_equal o.routes[2].stops.select{ |s| s.is_a? StopRest }.size, optim[2].size
    assert_equal o.routes.map{ |r| r.stops.size }.reduce(&:+), optim.flatten.size
  end

  test 'should return all or only active stops after optimization' do
    planning = plannings(:planning_one)
    inactive_stop = planning.routes.third.stops.second
    inactive_stop.update_attribute(:active, false)

    active_optim = planning.optimize(planning.routes, false, false) { |*a|
      optimizer_global(*a)
    }
    planning.set_stops(planning.routes, active_optim)
    active_stops = planning.routes.third.stops.map(&:id)

    all_optim = planning.optimize(planning.routes, false, true) { |*a|
      optimizer_global(*a)
    }
    planning.set_stops(planning.routes, all_optim, true)
    active_only = planning.routes.third.stops.map(&:id)

    assert_equal active_stops.size, active_only.size
    assert_not_equal active_stops, active_only
  end

  test 'should set stops from unaffected route to active after optimization' do
    planning = plannings(:planning_one)
    initial_inactive_stop = planning.routes.first.stops.first
    initial_inactive_stop.update_attribute(:active, false)

    active_optim = planning.optimize(planning.routes, false, false) { |*a|
      optimizer_global(*a)
    }
    planning.set_stops(planning.routes, active_optim)

    assert initial_inactive_stop.reload.active
  end

  test 'should set stops for one route' do
    route = routes(:route_one_one)
    original_order = route.stops.map(&:id)
    route.planning.set_stops([route], [original_order.reverse])
    assert_equal original_order.reverse, route.stops.map(&:id)
    route.planning.save!
    route.reload
    assert_equal original_order.reverse, route.stops.map(&:id)
  end

  test 'should set stops for planning' do
    planning = plannings(:planning_one)
    optim = planning.optimize(planning.routes, true) { |*a|
      optimizer_global(*a)
    }
    planning.set_stops(planning.routes, optim)
    assert_equal optim, planning.routes.map{ |r| r.stops.map(&:id) }
    planning.save!
    planning.reload
    assert_equal optim, planning.routes.map{ |r| r.stops.map(&:id) }
  end

  test 'should set stops with a geoloc rest in unassigned' do
    planning = plannings(:planning_one)
    unassigned = planning.routes.flat_map{ |r| r.stops.map(&:id) }
    planning.set_stops(planning.routes, [unassigned] + [[]] * (planning.routes.size - 1))
    assert planning.routes.flat_map{ |r| r.stops.select{ |s| s.is_a? StopRest }.map{ |s| s.route.vehicle_usage.id } }.size == planning.vehicle_usage_set.vehicle_usages.map(&:default_rest_duration?).size
    planning.save!
    planning.reload
    assert planning.routes.flat_map{ |r| r.stops.select{ |s| s.is_a? StopRest }.map{ |s| s.route.vehicle_usage.id } }.size == planning.vehicle_usage_set.vehicle_usages.map(&:default_rest_duration?).size
  end

  require Rails.root.join('test/lib/devices/tomtom_base')
  include TomtomBase

  test 'should fetch_stops_status' do
    o = plannings(:planning_one)
    o.customer.enable_stop_status = true
    add_tomtom_credentials(o.customer)
    set_route
    s = stops(:stop_one_one)
    assert !s.status
    with_stubs [:orders_service_wsdl, :show_order_report] do
      Planning.transaction do
        o.fetch_stops_status
        o.save!
      end
    end
    s.reload
    assert s.status
  end
end

class PlanningTestError < ActiveSupport::TestCase

  test 'should not compute because of router error' do
    o = plannings(:planning_one)
    Routers::RouterWrapper.stub_any_instance(:compute_batch, []) do
      assert_no_difference('Stop.count') do
        o.zoning_outdated = true
        o.compute
        o.save!
      end
    end
  end
end

class PlanningTestException < ActiveSupport::TestCase

  test 'should not compute because of router exception' do
    o = plannings(:planning_one)
    ApplicationController.stub_any_instance(:server_error, lambda { |*a| raise }) do
      Routers::RouterWrapper.stub_any_instance(:compute_batch, lambda { |*a| raise }) do
        assert_no_difference('Stop.count') do
          o.zoning_outdated = true
          assert_raises(RuntimeError) do
            o.compute
          end
        end
      end
    end
  end
end
