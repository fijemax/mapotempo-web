# Copyright © Mapotempo, 2013-2015
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
require 'optim/ort'

class OptimizerJob < Job.new(:planning_id, :route_id, :global, :active_only)
  @@optimize_time = Mapotempo::Application.config.optimize_time
  @@optimize_time_force = Mapotempo::Application.config.optimize_time_force
  @@max_split_size = Mapotempo::Application.config.optimize_max_split_size
  @@stop_soft_upper_bound = Mapotempo::Application.config.optimize_stop_soft_upper_bound
  @@vehicle_soft_upper_bound = Mapotempo::Application.config.optimize_vehicle_soft_upper_bound
  @@cluster_size = Mapotempo::Application.config.optimize_cluster_size
  @@cost_waiting_time = Mapotempo::Application.config.cost_waiting_time
  @@force_start = Mapotempo::Application.config.optimize_force_start

  def perform
    return true if @job.progress == 'no_solution' && @job.attempts > 0

    Delayed::Worker.logger.info "OptimizerJob planning_id=#{planning_id} perform"
    planning = Planning.where(id: planning_id).first!
    routes = planning.routes.select { |r|
      (route_id && r.id == route_id) || (!route_id && !global && r.vehicle_usage && r.size_active > 1) || (!route_id && global)
    }.reject(&:locked)
    optimize_time = planning.customer.optimization_time || @@optimize_time

    bars = Array.new(2, 0)
    optimum = unless routes.select(&:vehicle_usage).empty?
      begin
        planning.optimize(routes, global, active_only) do |positions, services, vehicles|
          optimum = Mapotempo::Application.config.optimize.optimize(
            positions, services, vehicles,
            optimize_time: @@optimize_time_force || (optimize_time ? optimize_time * 1000 : nil),
            max_split_size: planning.customer.optimization_max_split_size || @@max_split_size,
            stop_soft_upper_bound: planning.customer.optimization_stop_soft_upper_bound || @@stop_soft_upper_bound,
            vehicle_soft_upper_bound: planning.customer.optimization_vehicle_soft_upper_bound || @@vehicle_soft_upper_bound,
            cluster_threshold: planning.customer.cluster_size || @@cluster_size,
            cost_waiting_time: planning.customer.cost_waiting_time || @@cost_waiting_time,
            force_start: planning.customer.optimization_force_start.nil? ? @@force_start : planning.customer.optimization_force_start
          ) { |bar, computed, count|
            if bar
              if computed
                (0..bar).to_a.each { |i| bars[i] = (computed - 1) * 100 / count }
              else
                (0..(bar-1)).to_a.each { |i| bars[i] = 100 } if bar > 0
                bars[bar] = bar == 1 && (@@optimize_time_force || planning.customer.optimization_time) ? "#{(@@optimize_time_force || optimize_time) * 1000}ms0" : -1
              end
            end
            job_progress_save bars.join(';')
            Delayed::Worker.logger.info "OptimizerJob planning_id=#{planning_id} #{@job.progress}"
          }
          job_progress_save '100;100;-1'
          Delayed::Worker.logger.info "OptimizerJob planning_id=#{planning_id} #{@job.progress}"
          optimum
        end
      rescue NoSolutionFoundError => e
        job_progress_save 'no_solution'
        Delayed::Worker.logger.info "OptimizerJob planning_id=#{planning_id} #{@job.progress}"
        raise e
      end
    end

    # Apply result
    if optimum
      planning.set_stops(routes, optimum, active_only)
      routes.each { |r|
        r.reload # Refresh stops order
        r.compute
        r.save!
      }
      planning.reload
      planning.save!
    end
  rescue => e
    puts e.message
    puts e.backtrace.join("\n")
    raise e
  end
end
