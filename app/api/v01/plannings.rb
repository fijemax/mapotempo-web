# Copyright © Mapotempo, 2014-2016
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
require 'coerce'
require 'exceptions'

class V01::Plannings < Grape::API
  helpers SharedParams
  helpers do
    # Never trust parameters from the scary internet, only allow the white list through.
    def planning_params
      p = ActionController::Parameters.new(params)
      p = p[:planning] if p.key?(:planning)
      p[:zoning_ids] = [p[:zoning_id]] if p[:zoning_id] && (!p[:zoning_ids] || p[:zoning_ids].empty?)
      p.permit(:name, :ref, :date, :begin_date, :end_date, :active, :vehicle_usage_set_id, :tag_operation, tag_ids: [], zoning_ids: [])
    end

    ID_DESC = 'Id or the ref field value, then use "ref:[value]".'.freeze
  end

  # Planning get is located in plannings_get file because it needs to return specific content types (js, xml and ics)

  resource :plannings do
    desc 'Create planning.',
      detail: 'Create a planning. An out-of-route (unplanned) route and a route for each vehicle are automatically created. If some visits exist (or fetch if you use tags), as many stops as fetching visits will be created (ie: there is no specific operation to create routes and stops, the application create them for you).',
      nickname: 'createPlanning',
      success: V01::Entities::Planning
    params do
      use :params_from_entity, entity: V01::Entities::Planning.documentation.except(:id, :route_ids, :outdated, :tag_ids).deep_merge(
        name: { required: true },
        vehicle_usage_set_id: { required: true }
      )
      optional :tag_ids, type: Array[Integer], desc: 'Ids separated by comma.', coerce_with: CoerceArrayInteger, documentation: { param_type: 'form' }
      optional :geojson, type: Symbol, values: [:true, :false, :point, :polyline], default: :false, desc: 'Fill the geojson field with route geometry: `point` to return only points, `polyline` to return with encoded linestring.'
    end
    post do
      planning = current_customer.plannings.build(planning_params)
      planning.default_routes
      planning.compute
      planning.save_import!
      present planning, with: V01::Entities::Planning, geojson: params[:geojson]
    end

    desc 'Update planning.',
      nickname: 'updatePlanning',
      success: V01::Entities::Planning
    params do
      requires :id, type: String, desc: ID_DESC
      use :params_from_entity, entity: V01::Entities::Planning.documentation.except(:id, :route_ids, :outdated, :tag_ids)
      optional :geojson, type: Symbol, values: [:true, :false, :point, :polyline], default: :false, desc: 'Fill the geojson field with route geometry: `point` to return only points, `polyline` to return with encoded linestring.'
    end
    put ':id' do
      planning = current_customer.plannings.where(ParseIdsRefs.read(params[:id])).first!
      planning.update! planning_params
      present planning, with: V01::Entities::Planning, geojson: params[:geojson]
    end

    desc 'Delete planning.',
      nickname: 'deletePlanning'
    params do
      requires :id, type: String, desc: ID_DESC
    end
    delete ':id' do
      Route.includes_destinations.scoping do
        current_customer.plannings.where(ParseIdsRefs.read(params[:id])).first!.destroy
        status 204
      end
    end

    desc 'Delete multiple plannings.',
      nickname: 'deletePlannings'
    params do
      requires :ids, type: Array[String], desc: 'Ids separated by comma. You can specify ref (not containing comma) instead of id, in this case you have to add "ref:" before each ref, e.g. ref:ref1,ref:ref2,ref:ref3.', coerce_with: CoerceArrayString
    end
    delete do
      Route.includes_destinations.scoping do
        Planning.transaction do
          current_customer.plannings.select{ |planning|
            params[:ids].any?{ |s| ParseIdsRefs.match(s, planning) }
          }.each(&:destroy)
          status 204
        end
      end
    end

    desc 'Recompute the planning after parameter update.',
      detail: 'Refresh planning and outdated routes infos if inputs have been changed (for instance stores, destinations, visits, etc...)',
      nickname: 'refreshPlanning',
      success: V01::Entities::Planning
    params do
      requires :id, type: String, desc: ID_DESC
      optional :geojson, type: Symbol, values: [:true, :false, :point, :polyline], default: :false, desc: 'Fill the geojson field with route geometry: `point` to return only points, `polyline` to return with encoded linestring.'
    end
    get ':id/refresh' do
      Route.includes_destinations.scoping do
        planning = current_customer.plannings.where(ParseIdsRefs.read(params[:id])).first!
        raise Exceptions::JobInProgressError if Job.on_planning(planning.customer.job_optimizer, planning.id)
        planning.compute
        planning.save!
        present planning, with: V01::Entities::Planning, geojson: params[:geojson]
      end
    end

    desc 'Switch two vehicles.',
      detail: 'Switch vehicle associated to one route with another existing vehicle.',
      nickname: 'switchVehicles'
    params do
      requires :id, type: String, desc: ID_DESC
      requires :route_id, type: Integer, desc: 'Route id to switch associated vehicle.'
      requires :vehicle_usage_id, type: Integer, desc: 'New vehicle id to associate to the route.'
      optional :details, type: Boolean, desc: 'Output complete planning.', default: false
      optional :geojson, type: Symbol, values: [:true, :false, :point, :polyline], default: :false, desc: 'Fill the geojson field with route geometry: `point` to return only points, `polyline` to return with encoded linestring.'
    end
    patch ':id/switch' do
      Route.includes_destinations.scoping do
        planning = current_customer.plannings.where(ParseIdsRefs.read(params[:id])).first!
        raise Exceptions::JobInProgressError if Job.on_planning(planning.customer.job_optimizer, planning.id)
        route = planning.routes.find{ |route| route.id == Integer(params[:route_id]) }
        vehicle_usage = planning.vehicle_usage_set.vehicle_usages.find(params[:vehicle_usage_id])

        Planning.transaction do
          if route && vehicle_usage && planning.switch(route, vehicle_usage) && planning.save! && planning.compute && planning.save!
            if params[:details]
              present planning, with: V01::Entities::Planning, geojson: params[:geojson]
            else
              status 204
            end
          else
            status 400
          end
        end
      end
    end

    desc 'Insert one or more stop into planning routes.',
      detail: 'Insert automatically one or more stops in best routes and on best positions to have minimal influence on route\'s total time (this operation doesn\'t take into account time windows if they exist...). You should use this operation with existing stops in current planning\'s routes. In addition, you should not use this operation with many stops. You should use instead zoning (with automatic clustering creation for instance) to set multiple stops in each available route.',
      nickname: 'automaticInsertStop'
    params do
      requires :id, type: String, desc: ID_DESC
      requires :stop_ids, type: Array[Integer], desc: 'Ids separated by comma. You should not have too many stops.', documentation: { param_type: 'form' }, coerce_with: CoerceArrayInteger
      optional :max_time, type: Float, desc: 'Maximum time for best routes (in seconds).'
      optional :max_distance, type: Float, desc: 'Maximum distance for best routes (in meters).'
      optional :active_only, type: Boolean, desc: 'Use only active stops.', default: true
      optional :out_of_zone, type: Boolean, desc: 'Take into account points out of zones.', default: true
    end
    patch ':id/automatic_insert' do
      Route.includes_destinations.scoping do
        planning = current_customer.plannings.where(ParseIdsRefs.read(params[:id])).first!
        raise Exceptions::JobInProgressError if Job.on_planning(planning.customer.job_optimizer, planning.id)
        stops = planning.routes.flat_map{ |r| r.stops }.select{ |stop| params[:stop_ids].include?(stop.id) }

        begin
          Planning.transaction do
            stops.each do |stop|
              planning.automatic_insert(stop,
                max_time: params[:max_time],
                max_distance: params[:max_distance],
                out_of_zone: params[:out_of_zone],
                active_only: params[:active_only]) || raise(Exceptions::LoopError.new)
            end
            planning.compute
            planning.save!
            status 204
          end
        rescue Exceptions::LoopError => e
          status 400
        end
      end
    end

    desc 'Apply zonings.',
      detail: 'Apply zoning by assign stops to vehicles using the corresponding zones.',
      nickname: 'applyZonings'
    params do
      requires :id, type: String, desc: ID_DESC
      optional :details, type: Boolean, desc: 'Output route details', default: false
      optional :geojson, type: Symbol, values: [:true, :false, :point, :polyline], default: :false, desc: 'Fill the geojson field with route geometry: `point` to return only points, `polyline` to return with encoded linestring.'
    end
    get ':id/apply_zonings' do
      Route.includes_destinations.scoping do
        planning = current_customer.plannings.where(ParseIdsRefs.read(params[:id])).first!
        raise Exceptions::JobInProgressError if Job.on_planning(planning.customer.job_optimizer, planning.id)
        planning.zoning_outdated = true
        planning.compute
        planning.save! && planning.reload
        if params[:details]
          present planning, with: V01::Entities::Planning, geojson: params[:geojson]
        else
          status 204
        end
      end
    end

    desc 'Optimize routes.',
      detail: 'Optimize all unlocked routes by keeping visits in same route or not.',
      nickname: 'optimizeRoutes'
    params do
      requires :id, type: String, desc: ID_DESC
      optional :global, type: Boolean, desc: 'Use global optimization and move visits between routes if needed', default: false
      optional :details, type: Boolean, desc: 'Output route details', default: false
      optional :synchronous, type: Boolean, desc: 'Synchronous', default: true
      optional :all_stops, type: Boolean, desc: 'Deprecated (Use active_only instead)'
      optional :active_only, type: Boolean, desc: 'If true only active stops are taken into account by optimization, else inactive stops are also taken into account but are not activated in result route.', default: true
      optional :geojson, type: Symbol, values: [:true, :false, :point, :polyline], default: :false, desc: 'Fill the geojson field with route geometry: `point` to return only points, `polyline` to return with encoded linestring.'
    end
    get ':id/optimize' do
      Route.includes_destinations.scoping do
        planning = current_customer.plannings.where(ParseIdsRefs.read(params[:id])).first!
        raise Exceptions::JobInProgressError if planning.customer.job_optimizer
        begin
          Optimizer.optimize(planning, nil, params[:global], params[:synchronous], params[:all_stops].nil? ? params[:active_only] : !params[:all_stops])
        rescue NoSolutionFoundError
          status 304
        end

        if params[:details]
          present planning, with: V01::Entities::Planning, geojson: params[:geojson]
        else
          status 204
        end
      end
    end

    desc 'Clone the planning.',
      nickname: 'clonePlanning',
      success: V01::Entities::Planning
    params do
      requires :id, type: String, desc: ID_DESC
      optional :geojson, type: Symbol, values: [:true, :false, :point, :polyline], default: :false, desc: 'Fill the geojson field with route geometry: `point` to return only points, `polyline` to return with encoded linestring.'
    end
    patch ':id/duplicate' do
      Route.includes_destinations.scoping do
        planning = current_customer.plannings.where(ParseIdsRefs.read(params[:id])).first!
        planning = planning.duplicate
        planning.save!(validate: false)
        present planning, with: V01::Entities::Planning, geojson: params[:geojson]
      end
    end

    desc 'Use order_array in the planning.',
      detail: 'Only available if "order array" option is active for current customer.',
      nickname: 'useOrderArray',
      success: V01::Entities::Planning
    params do
      requires :id, type: String, desc: ID_DESC
      requires :order_array_id, type: Integer
      requires :shift, type: Integer
      optional :geojson, type: Symbol, values: [:true, :false, :point, :polyline], default: :false, desc: 'Fill the geojson field with route geometry: `point` to return only points, `polyline` to return with encoded linestring.'
    end
    patch ':id/order_array' do
      Route.includes_destinations.scoping do
        planning = current_customer.plannings.where(ParseIdsRefs.read(params[:id])).first!
        raise Exceptions::JobInProgressError if Job.on_planning(planning.customer.job_optimizer, planning.id)
        order_array = current_customer.order_arrays.find(params[:order_array_id])
        shift = Integer(params[:shift])
        planning.apply_orders(order_array, shift)
        planning.save!
        present planning, with: V01::Entities::Planning, geojson: params[:geojson]
      end
    end

    desc 'Update routes visibility and lock.',
      nickname: 'updateRoutes'
    params do
      requires :id, type: String, desc: ID_DESC
      requires :route_ids, type: Array[Integer], documentation: { param_type: 'form' }, coerce_with: CoerceArrayInteger, desc: 'Ids separated by comma.'
      requires :selection, type: String, values: %w(all reverse none)
      requires :action, type: String, values: %w(toggle lock)
    end
    patch ':id/update_routes' do
      planning = current_customer.plannings.where(ParseIdsRefs.read(params[:id])).first!
      routes = planning.routes.select{ |r| params[:route_ids].include? r.id }
      routes.each do |route|
        case params[:action].to_sym
          when :toggle
            case params[:selection].to_sym
              when :all
                route.update! hidden: false
              when :reverse
                route.update! hidden: !route.hidden
              when :none
                route.update! hidden: true
            end
          when :lock
            case params[:selection].to_sym
              when :all
                route.update! locked: true
              when :reverse
                route.update! locked: !route.locked
              when :none
                route.update! locked: false
            end
        end
      end

      present routes, with: V01::Entities::RouteProperties
    end

    desc 'Update stops status.',
      detail: 'Update stops status from remote devices. Only available if enable_stop_status is true for customer.',
      nickname: 'updateStopsStatus',
      success: V01::Entities::Planning
    params do
      requires :id, type: String, desc: ID_DESC
      optional :details, type: Boolean, desc: 'Output route details', default: false
    end
    patch ':id/update_stops_status' do
      Route.includes_destinations.scoping do
        planning = current_customer.plannings.where(ParseIdsRefs.read(params[:id])).first!
        if Job.on_planning(planning.customer.job_optimizer, planning.id)
          status 204
        else
          planning.fetch_stops_status
          planning.save!
          if params[:details]
            present planning.routes, with: V01::Entities::RouteStatus
          else
            status 204
          end
        end
      end
    end
  end
end
