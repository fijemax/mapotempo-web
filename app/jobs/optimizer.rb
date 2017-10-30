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
require 'optimizer_job'

class Optimizer
  @@optimize_time = Mapotempo::Application.config.optimize_time
  @@optimize_time_force = Mapotempo::Application.config.optimize_time_force
  @@max_split_size = Mapotempo::Application.config.optimize_max_split_size
  @@stop_soft_upper_bound = Mapotempo::Application.config.optimize_stop_soft_upper_bound
  @@vehicle_soft_upper_bound = Mapotempo::Application.config.optimize_vehicle_soft_upper_bound
  @@cluster_size = Mapotempo::Application.config.optimize_cluster_size
  @@cost_waiting_time = Mapotempo::Application.config.cost_waiting_time
  @@force_start = Mapotempo::Application.config.optimize_force_start

  def self.optimize(planning, route, global = false, synchronous = false, active_only = true)
    optimize_time = planning.customer.optimization_time || @@optimize_time
    if route && route.size_active <= 1 && active_only
      # Nothing to optimize
      route.compute
      planning.save
    elsif !synchronous && Mapotempo::Application.config.delayed_job_use
      if planning.customer.job_optimizer
        # Customer already run an optimization
        planning.errors.add(:base, I18n.t('errors.planning.already_optimizing'))
        false
      else
        planning.customer.job_optimizer = Delayed::Job.enqueue(OptimizerJob.new(planning.id, route && route.id, global, active_only))
        planning.customer.job_optimizer.save!
      end
    else
      routes = planning.routes.select { |r|
        (route && r.id == route.id) || (!route && !global && r.vehicle_usage && r.size_active > 1) || (!route && global)
      }.reject(&:locked)
      optimum = unless routes.select(&:vehicle_usage).empty?
        planning.optimize(routes, global, active_only) do |positions, services, vehicles|
          Mapotempo::Application.config.optimize.optimize(
            positions, services, vehicles,
            optimize_time: @@optimize_time_force || (optimize_time ? optimize_time * 1000 : nil),
            max_split_size: planning.customer.optimization_max_split_size || @@max_split_size,
            stop_soft_upper_bound: planning.customer.optimization_stop_soft_upper_bound || @@stop_soft_upper_bound,
            vehicle_soft_upper_bound: planning.customer.optimization_vehicle_soft_upper_bound || @@vehicle_soft_upper_bound,
            cluster_threshold: planning.customer.cluster_size || @@cluster_size,
            cost_waiting_time: planning.customer.cost_waiting_time || @@cost_waiting_time,
            force_start: planning.customer.optimization_force_start.nil? ? @@force_start : planning.customer.optimization_force_start
          )
        end
      end

      if optimum
        planning.set_stops(routes, optimum, active_only)
        routes.each{ |r|
          r.reload # Refresh stops order
          r.compute
          r.save!
        }
        planning.reload
        planning.save!
      else
        false
      end
    end
  end
end
