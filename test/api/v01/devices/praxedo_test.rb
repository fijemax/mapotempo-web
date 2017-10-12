# Copyright © Mapotempo, 2017
#
# This file is part of Mapotempo.
#
# Mapotempo is free software. You can redistribute it and/or
# modify since you respect the terms of the GNU Affero General
# Public License as published by the Free Software Foundation,
# either version 3 of the License, or (at your option) any later version.
#
# Mapotempo is distributed in the hope that it will be useful, but WITHOUT
# ANY WARRANTY; without even the implied warranty of MERCHANTABILITY
# or FITNESS FOR A PARTICULAR PURPOSE.  See the Licenses for more details.
#
# You should have received a copy of the GNU Affero General Public License
# along with Mapotempo. If not, see:
# <http://www.gnu.org/licenses/agpl.html>
#
require 'test_helper'

class V01::Devices::PraxedoTest < ActiveSupport::TestCase
  include Rack::Test::Methods

  require Rails.root.join('test/lib/devices/api_base')
  include ApiBase

  require Rails.root.join('test/lib/devices/praxedo_base')
  include PraxedoBase

  setup do
    @customer = add_praxedo_credentials(customers(:customer_one))
  end

  def planning_api(part = nil, param = {})
    part = part ? '/' + part.to_s : ''
    "/api/0.1/plannings#{part}.json?api_key=testkey1&" + param.collect { |k, v| "#{k}=" + URI.escape(v.to_s) }.join('&')
  end

  test 'authenticate' do
    with_stubs [:get_events_wsdl, :get_events] do
      get api("devices/praxedo/auth/#{@customer.id}", params_for(:praxedo, @customer))
      assert_equal 204, last_response.status
    end
  end

  test 'send route' do
    with_stubs [:create_events_wsdl, :create_events] do
      set_route
      post api('devices/praxedo/send', { customer_id: @customer.id, route_id: @route.id })
      assert_equal 201, last_response.status, last_response.body
      @route.reload
      assert @route.reload.last_sent_at

      assert_equal(
        {
          'id' => @route.id,
          'last_sent_to' => 'Praxedo',
          'last_sent_at' => @route.last_sent_at.iso8601(3),
          'last_sent_at_formatted' => I18n.l(@route.last_sent_at)
        },
        JSON.parse(last_response.body))
    end
  end

  test 'fetch stops and update quantities' do
    customers(:customer_one).update(job_optimizer_id: nil)
    # All 3 stops in route are completed
    # with following quantities from Praxedo:
    # 0 => 30kg / 1 => 10kg / 2 => 5kg ==> 45kg
    with_stubs [:search_events_wsdl, :search_events] do
      @customer.update_attribute(:enable_stop_status, true)
      set_route
      planning = @route.planning

      patch planning_api("#{planning.id}/update_stops_status", details: true)
      assert_equal 200, last_response.status

      stops_status = JSON.parse(last_response.body)
      du_ids = @customer.deliverable_units.map(&:id)
      kg_du = @customer.deliverable_units.select { |du| du.label == 'kg' }.first
      stops_status.last['quantities'].map do |quantity|
        assert du_ids.include?(quantity['deliverable_unit_id'])
        if kg_du.id == quantity['deliverable_unit_id']
          assert_equal quantity['quantity'], 45
        end
      end

      # Check for visit update
      updated_quantities = [5, 10, 30]
      @route.stops.each_with_index do |stop, i|
        if stop.is_a?(StopVisit)
          visit = stop.visit.reload
          assert_equal visit.quantities[2], updated_quantities[i]
        end
      end
    end
  end

end
