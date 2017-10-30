# Copyright © Mapotempo, 2014-2015
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

class V01::Customers < Grape::API
  helpers SharedParams
  helpers do
    # Never trust parameters from the scary internet, only allow the white list through.
    def customer_params
      p = ActionController::Parameters.new(params)
      p = p[:customer] if p.key?(:customer)

      customer = @current_user.admin? && params[:id] ? @current_user.reseller.customers.where(ParseIdsRefs.read(params[:id])).first! : @current_user.customer

      p[:devices] = p[:devices] ? JSON.parse(p[:devices], symbolize_names: true) : {}
      p[:devices] = customer[:devices].deep_merge(p[:devices]) if customer && customer[:devices].size > 0

      if @current_user.admin?
        p.permit(:ref, :name, :end_subscription, :max_vehicles, :take_over, :print_planning_annotating, :print_header, :router_id, :router_dimension, :test, :optimization_cluster_size, :optimization_time, :optimization_stop_soft_upper_bound, :optimization_vehicle_soft_upper_bound, :cost_waiting_time, :profile_id, :default_country, :reseller_id, :print_stop_time, :speed_multiplicator, :enable_references, :enable_multi_vehicle_usage_sets, :enable_multi_visits, :advanced_options, :enable_external_callback, :external_callback_url, :external_callback_name, :description, :enable_global_optimization, :enable_vehicle_position, :enable_stop_status, :optimization_force_start, router_options: [:time, :distance, :isochrone, :isodistance, :avoid_zones, :track, :motorway, :toll, :trailers, :weight, :weight_per_axle, :height, :width, :length, :hazardous_goods, :max_walk_distance, :approach, :snap, :strict_restriction], devices: permit_recursive_params(p[:devices]))
      else
        p.permit(:take_over, :print_planning_annotating, :print_header, :router_id, :router_dimension, :default_country, :print_stop_time, :speed_multiplicator, :advanced_options, :enable_external_callback, :external_callback_url, :external_callback_name, :optimization_force_start, router_options: [:time, :distance, :isochrone, :isodistance, :avoid_zones, :track, :motorway, :toll, :trailers, :weight, :weight_per_axle, :height, :width, :length, :hazardous_goods, :max_walk_distance, :approach, :snap, :strict_restriction], devices: permit_recursive_params(p[:devices]))
      end
    end

    def permit_recursive_params(params)
      if !params.nil?
        params.map do |key, value|
          if value.is_a?(Array)
            { key => [ permit_recursive_params(value.first) ] }
          elsif value.is_a?(Hash) || value.is_a?(ActionController::Parameters)
            { key => permit_recursive_params(value) }
          else
            key
          end
        end
      end
    end

    ID_DESC = 'Id or the ref field value, then use "ref:[value]".'.freeze
  end

  resource :customers do
    desc 'Fetch customers.',
      detail: 'Only available with an admin api_key.',
      nickname: 'getCustomers',
      is_array: true,
      success: V01::Entities::Customer
    get do
      if @current_user.admin?
        present @current_user.reseller.customers, with: V01::Entities::CustomerAdmin
      else
        error! 'Forbidden', 403
      end
    end

    desc 'Fetch customer.',
      nickname: 'getCustomer',
      is_array: true,
      success: V01::Entities::Customer
    params do
      requires :id, type: String, desc: ID_DESC
    end
    get ':id' do
      if @current_user.admin?
        customer = @current_user.reseller.customers.where(ParseIdsRefs.read(params[:id])).first!
        present customer, with: V01::Entities::CustomerAdmin
      elsif ParseIdsRefs.match params[:id], @current_customer
        present @current_customer, with: V01::Entities::Customer
      else
        status 404
      end
    end

    desc 'Update customer.',
      nickname: 'updateCustomer',
      success: V01::Entities::Customer
    params do
      requires :id, type: String, desc: ID_DESC
      use :params_from_entity, entity: V01::Entities::Customer.documentation.except(
        :id,
        :store_ids,
        :vehicle_usage_set_ids,
        :deliverable_unit_ids,
        :job_destination_geocoding_id,
        :job_store_geocoding_id,
        :job_optimizer_id,
        :router_options,
        :take_over,
        :devices
      )

      optional :router_options, type: Hash do
        optional :track, type: Boolean
        optional :motorway, type: Boolean
        optional :toll, type: Boolean
        optional :trailers, type: Integer
        optional :weight, type: Float
        optional :weight_per_axle, type: Float
        optional :height, type: Float
        optional :width, type: Float
        optional :length, type: Float
        optional :hazardous_goods, type: String
        optional :max_walk_distance, type: Float
        optional :approach, type: String
        optional :snap, type: Float
        optional :strict_restriction, type: Boolean
      end

      optional :take_over, type: Integer, documentation: { type: 'string', desc: 'Schedule time (HH:MM)' }, coerce_with: ->(value) { ScheduleType.new.type_cast(value) }
    end
    put ':id' do
      if @current_user.admin?
        customer = @current_user.reseller.customers.where(ParseIdsRefs.read(params[:id])).first!
        customer.update! customer_params
        present customer, with: V01::Entities::CustomerAdmin
      elsif ParseIdsRefs.match params[:id], @current_customer
        @current_customer.update! customer_params
        present @current_customer, with: V01::Entities::Customer
      else
        status 404
      end
    end

    desc 'Create customer.',
      detail: 'Only available with an admin api_key.',
      nickname: 'createCustomer',
      success: V01::Entities::Customer
    params do
      use :params_from_entity, entity: V01::Entities::Customer.documentation.except(
        :id,
        :store_ids,
        :vehicle_usage_set_ids,
        :deliverable_unit_ids,
        :job_destination_geocoding_id,
        :job_store_geocoding_id,
        :job_optimizer_id,
        :router_options,
        :take_over
      ).deep_merge(
        name: { required: true },
        default_country: { required: true },
        router_id: { required: true },
        profile_id: { required: true }
      )

      optional :router_options, type: Hash do
        optional :track, type: Boolean
        optional :motorway, type: Boolean
        optional :toll, type: Boolean
        optional :trailers, type: Integer
        optional :weight, type: Float
        optional :weight_per_axle, type: Float
        optional :height, type: Float
        optional :width, type: Float
        optional :length, type: Float
        optional :hazardous_goods, type: String
        optional :max_walk_distance, type: Float
      end

      optional :take_over, type: Integer, documentation: { type: 'string', desc: 'Schedule time (HH:MM)' }, coerce_with: ->(value) { ScheduleType.new.type_cast(value) }
    end
    post do
      if @current_user.admin?
        customer = @current_user.reseller.customers.build(customer_params)
        @current_user.reseller.save!
        present customer, with: V01::Entities::CustomerAdmin
      else
        error! 'Forbidden', 403
      end
    end

    desc 'Delete customer.',
      detail: 'Only available with an admin api_key.',
      nickname: 'deleteCustomer'
    params do
      requires :id, type: String, desc: ID_DESC
    end
    delete ':id' do
      if @current_user.admin?
        id = ParseIdsRefs.read(params[:id])
        @current_user.reseller.customers.where(id).first!.destroy
        status 204
      else
        error! 'Forbidden', 403
      end
    end

    desc 'Return a job.',
      detail: 'Return asynchronous job (like geocoding, optimizer) currently runned for the customer.',
      nickname: 'getJob'
    params do
      requires :id, type: String, desc: ID_DESC
      requires :job_id, type: Integer
    end
    get ':id/job/:job_id' do
      customer = @current_user.admin? ?
        @current_user.reseller.customers.where(ParseIdsRefs.read(params[:id])).first! :
        ParseIdsRefs.match(params[:id], @current_customer) ? @current_customer : nil
      if customer
        if customer.job_optimizer && customer.job_optimizer_id == params[:job_id]
          customer.job_optimizer
        elsif customer.job_destination_geocoding && customer.job_destination_geocoding_id == params[:job_id]
          customer.job_destination_geocoding
        elsif customer.job_store_geocoding && customer.job_store_geocoding_id == params[:job_id]
          customer.job_store_geocoding
        end
      else
        status 404
      end
    end

    desc 'Cancel job.',
      detail: 'Cancel asynchronous job (like geocoding, optimizer) currently runned for the customer.',
      nickname: 'deleteJob'
    params do
      requires :id, type: String, desc: ID_DESC
      requires :job_id, type: Integer
    end
    delete ':id/job/:job_id' do
      customer = @current_user.admin? ?
        @current_user.reseller.customers.where(ParseIdsRefs.read(params[:id])).first! :
        ParseIdsRefs.match(params[:id], @current_customer) ? @current_customer : nil
      if customer
        if customer.job_optimizer && customer.job_optimizer_id == params[:job_id]
          customer.job_optimizer.destroy
        elsif customer.job_destination_geocoding && customer.job_destination_geocoding_id == params[:job_id]
          customer.job_destination_geocoding.destroy
        elsif customer.job_store_geocoding && customer.job_store_geocoding_id == params[:job_id]
          customer.job_store_geocoding.destroy
        end
        status 204
      else
        status 404
      end
    end

    desc 'Duplicate customer.',
      detail: 'Create a copy of customer. Only available with an admin api_key.',
      nickname: 'duplicateCustomer'
    params do
      requires :id, type: String, desc: ID_DESC
      optional :exclude_users, type: Boolean, default: false
    end
    put ':id/duplicate' do
      if @current_user.admin?
        customer = @current_user.reseller.customers.where(ParseIdsRefs.read(params[:id])).first!
        customer.exclude_users = params[:exclude_users]
        customer = customer.duplicate
        customer.save!(validate: false)

        present customer, with: V01::Entities::CustomerAdmin
      else
        error! 'Forbidden', 403
      end
    end
  end
end
