# Copyright © Mapotempo, 2015-2016
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
module FleetBuilder
  def build_route_with_missions(route, customer)
    destinations = []
    departure = route.vehicle_usage.default_store_start
    index_counter = -1

    destinations << {
      index: index_counter += 1,
      mission_type: 'departure',
      external_ref: generate_store_id(departure, route, p_time(route, route.start), type: 'departure'),
      name: departure.name,
      date: p_time(route, route.start).strftime('%FT%T.%L%:z'),
      duration: route.vehicle_usage.default_service_time_start,
      location: {
        lat: departure.lat,
        lon: departure.lng
      },
      address: {
        city: departure.city,
        country: departure.country || customer.default_country,
        postalcode: departure.postalcode,
        state: departure.state,
        street: departure.street
      }
    } if departure

    destinations += route.stops.select{ |stop| stop.active? && stop.time }.sort_by(&:index).map do |destination|
      visit = destination.is_a?(StopVisit)
      # labels = visit ? (destination.visit.tags + destination.visit.destination.tags).map(&:label).join(', ') : nil

      time_windows = []
      time_windows << {
        start: p_time(route, destination.open1).strftime('%FT%T.%L%:z'),
        end: p_time(route, destination.close1).strftime('%FT%T.%L%:z')
      } if visit && destination.open1 && destination.close1
      time_windows << {
        start: p_time(route, destination.open2).strftime('%FT%T.%L%:z'),
        end: p_time(route, destination.close2).strftime('%FT%T.%L%:z')
      } if visit && destination.open2 && destination.close2

      {
        mission_type: visit ? 'mission' : 'rest',
        external_ref: generate_mission_id(destination, planning_date(route.planning)),
        name: destination.name,
        date: p_time(route, destination.time).strftime('%FT%T.%L%:z'),
        duration: destination.duration,
        planned_travel_time: destination.drive_time,
        planned_distance: destination.distance,
        location: {
          lat: destination.lat,
          lon: destination.lng
        },
        comment: visit ? [
          destination.comment,
          # destination.priority ? I18n.t('activerecord.attributes.visit.priority') + I18n.t('text.separator') + destination.priority_text : nil,
          # labels.present? ? I18n.t('activerecord.attributes.visit.tags') + I18n.t('text.separator') + labels : nil,
        ].compact.join("\r\n\r\n").strip : nil,
        phone: visit ? destination.phone_number : nil,
        reference: visit ? destination.visit.destination.ref : nil,
        address: {
          city: destination.city,
          country: destination.country || customer.default_country,
          detail: destination.detail,
          postalcode: destination.postalcode,
          state: destination.state,
          street: destination.street
        },
        time_windows: visit ? time_windows : nil,
        quantities: destination.is_a?(StopVisit) && !customer.enable_orders ? VisitQuantities.normalize(destination.visit, route.vehicle_usage.try(&:vehicle)) : nil,
        index: index_counter += 1,
      }.compact
    end

    arrival = route.vehicle_usage.default_store_stop
    destinations << {
      index: index_counter += 1,
      mission_type: 'arrival',
      external_ref: generate_store_id(arrival, route, p_time(route, route.end), type: 'arrival'),
      name: arrival.name,
      date: p_time(route, route.end).strftime('%FT%T.%L%:z'),
      duration: route.vehicle_usage.default_service_time_end,
      planned_travel_time: route.stop_drive_time,
      planned_distance: route.stop_distance,
      location: {
        lat: arrival.lat,
        lon: arrival.lng
      },
      address: {
        city: arrival.city,
        country: arrival.country || customer.default_country,
        postalcode: arrival.postalcode,
        state: arrival.state,
        street: arrival.street
      }
    } if arrival

    build_route(route, destinations)
  end

  def build_route(route, destinations = nil)
    {
      user_id: convert_user(route.vehicle_usage.vehicle.devices[:fleet_user]),
      name: route.ref || route.vehicle_usage.vehicle.ref || route.vehicle_usage.vehicle.name,
      date: p_time(route, route.start).strftime('%FT%T.%L%:z'),
      external_ref: generate_route_id(route, p_time(route, route.start)),
      missions: destinations
    }
  end
end
