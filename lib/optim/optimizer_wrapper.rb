# Copyright © Mapotempo, 2016
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
require 'rest_client'

class NoSolutionFoundError < StandardError; end

class OptimizerWrapper

  attr_accessor :cache, :url, :api_key

  def initialize(cache, url, api_key)
    @cache, @url, @api_key = cache, url, api_key
  end

  # positions with stores at the end
  # services Array[Hash{start1: , end1: , duration: , stop_id: , vehicle_id: , quantities: []}]
  # vehicles Array[Hash{id: , open: , close: , stores: [], rests: [], capacities: []}]
  def optimize(positions, services, vehicles, options, &progress)
    key = Digest::MD5.hexdigest(Marshal.dump([positions, services, vehicles, options]))

    result = @cache.read(key)
    if !result
      stores = vehicles.flat_map{ |v| v[:stores] }
      rests = vehicles.flat_map{ |v| v[:rests] }
      shift_stores = 0
      services_with_negative_quantities = []

      vrp = {
        units: vehicles.flat_map{ |v| v[:capacities] && v[:capacities].map{ |c| c[:deliverable_unit_id] } }.uniq.map{ |k|
          {id: "u#{k}"}
        },
        points: positions.each_with_index.collect{ |pos, i|
          {
            id: "p#{i}",
            location: {
              lat: pos[0],
              lon: pos[1]
            }
          }
        },
        rests: rests.collect{ |rest|
          {
            id: "r#{rest[:stop_id]}",
            timewindows: [{
              start: rest[:start1],
              end: rest[:end1]
            }],
            duration: rest[:duration]
          }
        },
        vehicles: vehicles.collect{ |vehicle|
          v = {
            id: "v#{vehicle[:id]}",
            router_mode: vehicle[:router].mode,
            router_dimension: vehicle[:router_dimension],
            # router_options are flattened and merged below
            speed_multiplier: vehicle[:speed_multiplier],
            area: vehicle[:speed_multiplier_areas] ? vehicle[:speed_multiplier_areas].map{ |a| a[:area].join(',') }.join('|') : nil,
            speed_multiplier_area: vehicle[:speed_multiplier_areas] ? vehicle[:speed_multiplier_areas].map{ |a| a[:speed_multiplicator_area] }.join('|') : nil,
            timewindow: {start: vehicle[:open], end: vehicle[:close]},
            start_point_id: vehicle[:stores].include?(:start) ? "p#{shift_stores + services.size}" : nil,
            end_point_id: vehicle[:stores].include?(:stop) ? "p#{vehicle[:stores].size - 1 + shift_stores + services.size}" : nil,
            cost_fixed: 0,
            cost_distance_multiplier: vehicle[:router_dimension] == 'distance' ? 1 : 0,
            cost_time_multiplier: vehicle[:router_dimension] == 'time' ? 1 : 0,
            cost_waiting_time_multiplier: vehicle[:router_dimension] == 'time' ? options[:cost_waiting_time] : 0,
            # FIXME: ortools is not able to support non null late multipliers both services & multiple vehicles
            cost_late_multiplier: (options[:vehicle_soft_upper_bound] && options[:vehicle_soft_upper_bound] > 0 && (!options[:stop_soft_upper_bound] || options[:stop_soft_upper_bound] == 0 || vehicles.size == 1 || services.all?{ |s| s[:vehicle_id] })) ? options[:vehicle_soft_upper_bound] : nil,
            force_start: options[:force_start],
            rest_ids: vehicle[:rests].collect{ |rest|
              "r#{rest[:stop_id]}"
            },
            capacities: vehicle[:capacities] ? vehicle[:capacities].map{ |c|
              c[:capacity] && c[:overload_multiplier] >= 0 ? {
                unit_id: "u#{c[:deliverable_unit_id]}",
                limit: c[:capacity],
                overload_multiplier: c[:overload_multiplier]
              } : nil
            }.compact : []
          }.merge(vehicle[:router_options] || {})
          shift_stores += vehicle[:stores].size
          v
        },
        services: services.each_with_index.collect{ |service, index|
          services_with_negative_quantities.push("s#{service[:stop_id]}") if service[:quantities] && service[:quantities].values.any?{ |q| q && q < 0 }
          {
            id: "s#{service[:stop_id]}",
            type: 'service',
            sticky_vehicle_ids: service[:vehicle_id] ? ["v#{service[:vehicle_id]}"] : nil, # to force an activity on a vehicle (for instance geoloc rests)
            activity: {
              point_id: "p#{index}",
              timewindows: [
                (service[:start1] || service[:end1]) && {
                  start: service[:start1],
                  end: service[:end1]
                },
                (service[:start2] || service[:end2]) && {
                  start: service[:start2],
                  end: service[:end2]
                },
              ].compact,
              duration: service[:duration],
              late_multiplier: (options[:stop_soft_upper_bound] && options[:stop_soft_upper_bound] > 0) ? options[:stop_soft_upper_bound] : nil
            },
            quantities: service[:quantities] ? service[:quantities].each.map{ |k, v|
              v ? {
                unit_id: "u#{k}",
                value: v
              } : nil
            }.compact : []
          }.delete_if{ |k, v| !v }
        },
        relations: [{
          id: :never_first,
          type: :never_first,
          linked_ids: services_with_negative_quantities
        }],
        configuration: {
          preprocessing: {
            cluster_threshold: options[:cluster_threshold],
            prefer_short_segment: true
          },
          resolution: {
            duration: options[:optimize_time] ? options[:optimize_time] * vehicles.size : nil,
            iterations_without_improvment: 100,
            initial_time_out: 3000 * vehicles.size,
            time_out_multiplier: 2
          }  }
      }

      resource_vrp = RestClient::Resource.new(@url + '/vrp/submit.json', timeout: nil)
      json = resource_vrp.post({api_key: @api_key, vrp: vrp}.to_json, content_type: :json, accept: :json)

      result = nil
      while json
        result = JSON.parse(json)
        if result['job']['status'] == 'completed'
          @cache.write(key, json.body)
          break
        elsif ['queued', 'working'].include?(result['job']['status'])
          if progress && m = /^(process ([0-9]+)\/([0-9]+) \- )?([a-z ]+)/.match(result['job']['avancement'])
            progress.call(m[4].start_with?('compute matrix') ? 0 : m[4].start_with?('run optimization') ? 1 : nil, m[1] && m[2].to_i, m[2] && m[3].to_i)
          end
          sleep(2)
          job_id = result['job']['id']
          json = RestClient.get(@url + "/vrp/jobs/#{job_id}.json", params: {api_key: @api_key})
        else
          if /No solution provided/.match result['job']['avancement']
            raise NoSolutionFoundError.new
          else
            raise RuntimeError.new(result['job']['avancement'] || 'Optimizer return unknown error')
          end
        end
      end
    else
      result = JSON.parse(result)
    end

    [result['solutions'][0]['unassigned'] ? result['solutions'][0]['unassigned'].collect{ |activity|
      activity['service_id'][1..-1].to_i
    } : []] + vehicles.collect{ |vehicle|
      route = result['solutions'][0]['routes'].find{ |r| r['vehicle_id'] == "v#{vehicle[:id]}" }
      !route ? [] : route['activities'].collect{ |activity|
        if activity.key?('service_id')
          activity['service_id'][1..-1].to_i
        elsif activity.key?('rest_id')
          activity['rest_id'][1..-1].to_i
        end
      }.compact # stores are not returned anymore
    }
  end
end
