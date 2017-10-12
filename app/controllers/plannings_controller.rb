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
require 'csv'
require 'value_to_boolean'
require 'zip'

class PlanningsController < ApplicationController
  before_action :authenticate_user!
  before_action :set_planning, only: [:show, :edit, :update, :destroy, :move, :refresh, :switch, :automatic_insert, :update_stop, :optimize_route, :active, :duplicate, :reverse_order, :apply_zonings, :optimize]
  before_action :check_no_existing_job, only: [:move, :refresh, :switch, :automatic_insert, :update_stop, :optimize_route, :active, :reverse_order, :apply_zonings, :optimize]
  around_action :includes_destinations, except: [:index, :show, :new, :create]

  load_and_authorize_resource

  include PlanningExport

  def index
    @plannings = current_user.customer.plannings.select{ |planning|
      !params.key?(:ids) || (params[:ids] && params[:ids].split(',').include?(planning.id.to_s))
    }
    @customer = current_user.customer
    @spreadsheet_columns = export_columns
    @params = params
    respond_to do |format|
      format.html
      format.json
      format_csv(format)
    end
  end

  def show
    @params = params
    @routes = if params[:route_ids]
      route_ids = params[:route_ids].split(',').map{ |s| Integer(s) }
      @planning.routes.select{ |r| route_ids.include?(r.id) }
    end
    respond_to do |format|
      format.html
      format.json
      format.gpx do
        @gpx_track = !!params['track']
        response.headers['Content-Disposition'] = 'attachment; filename="' + filename + '.gpx"'
      end
      format.kml do
        response.headers['Content-Disposition'] = 'attachment; filename="' + filename + '.kml"'
        render 'plannings/show', locals: { planning: @planning }
      end
      format.kmz do
        if params[:email]
          @planning.routes.includes_vehicle_usages.joins(vehicle_usage: [:vehicle]).each do |route|
            next if !route.vehicle_usage.vehicle.contact_email
            vehicle = route.vehicle_usage.vehicle
            content = kmz_string_io(route: route, with_home_markers: true).string
            name = export_filename route.planning, route.ref || route.vehicle_usage.vehicle.name
            if Mapotempo::Application.config.delayed_job_use
              RouteMailer.delay.send_kmz_route current_user, I18n.locale, vehicle, route, name + '.kmz', content
            else
              RouteMailer.send_kmz_route(current_user, I18n.locale, vehicle, route, name + '.kmz', content).deliver_now
            end
          end
          head :no_content
        else
          send_data kmz_string_io(planning: @planning, with_home_markers: true).string,
            type: 'application/vnd.google-earth.kmz',
            filename: filename + '.kmz'
        end
      end
      format_csv(format)
    end
  end

  def new
    @planning = current_user.customer.plannings.build
    @planning.vehicle_usage_set = current_user.customer.vehicle_usage_sets[0]
  end

  def edit
    @spreadsheet_columns = export_columns
    capabilities
  end

  def create
    respond_to do |format|
      Planning.transaction do
        @planning = current_user.customer.plannings.build(planning_params)
        @planning.default_routes
        if @planning.compute && @planning.save_import
          format.html { redirect_to edit_planning_path(@planning), notice: t('activerecord.successful.messages.created', model: @planning.class.model_name.human) }
        else
          format.html { render action: 'new' }
        end
      end
    end
  end

  def update
    respond_to do |format|
      if @planning.update(planning_params)
        format.html { redirect_to edit_planning_path(@planning), notice: t('activerecord.successful.messages.updated', model: @planning.class.model_name.human) }
      else
        capabilities
        format.html { render action: 'edit' }
      end
    end
  end

  def destroy
    @planning.destroy
    respond_to do |format|
      format.html { redirect_to plannings_url }
    end
  end

  def destroy_multiple
    Planning.transaction do
      if params['plannings']
        ids = params['plannings'].keys.collect{ |i| Integer(i) }
        current_user.customer.plannings.select{ |planning| ids.include?(planning.id) }.each(&:destroy)
      end
      respond_to do |format|
        format.html { redirect_to plannings_url }
      end
    end
  end

  def move
    respond_to do |format|
      begin
        Planning.transaction do
          route = @planning.routes.find{ |route| route.id == Integer(params[:route_id]) }
          stop = nil
          @planning.routes.find{ |route| stop = route.stops.find{ |stop| stop.id == Integer(params[:stop_id]) } }
          stop_route_id_was = stop.route.id
          # save! is used to rollback all the transaction with associations
          if @planning.move_stop(route, stop, params[:index] ? Integer(params[:index]) : nil) && @planning.compute && @planning.save!
            @planning.reload
            @routes = [route]
            @routes << @planning.routes.find{ |route| route.id == stop_route_id_was } if stop_route_id_was != route.id
            format.json { render action: 'show', location: @planning }
          else
            format.json { render json: @planning.errors, status: :unprocessable_entity }
          end
        end
      rescue ActiveRecord::RecordInvalid => e
        format.json { render json: @planning.errors, status: :unprocessable_entity }
      end
    end
  end

  def refresh
    respond_to do |format|
      @planning.compute
      if @planning.save
        format.json { render action: 'show', location: @planning }
      else
        format.json { render json: @planning.errors, status: :unprocessable_entity }
      end
    end
  end

  def switch
    respond_to do |format|
      begin
        Planning.transaction do
          route = @planning.routes.find{ |route| route.id == Integer(params[:route_id]) }
          vehicle_usage_id_was = route.vehicle_usage.id
          vehicle_usage = @planning.vehicle_usage_set.vehicle_usages.find(Integer(params[:vehicle_usage_id]))
          if route && vehicle_usage && @planning.switch(route, vehicle_usage) && @planning.save! && @planning.compute && @planning.save!
            @routes = [route]
            @routes << @planning.routes.find{ |route| route.vehicle_usage && route.vehicle_usage.id == vehicle_usage_id_was } if vehicle_usage_id_was != route.vehicle_usage.id
            format.json { render action: 'show', location: @planning }
          else
            format.json { render json: @planning.errors, status: :unprocessable_entity }
          end
        end
      rescue ActiveRecord::RecordInvalid => e
        format.json { render json: @planning.errors, status: :unprocessable_entity }
      end
    end
  end

  def automatic_insert
    respond_to do |format|
      begin
        if params[:stop_ids] && !params[:stop_ids].empty?
          stop_ids = params[:stop_ids].collect{ |id| Integer(id) }
          stops = @planning.routes.flat_map{ |r| r.stops.select{ |s| stop_ids.include? s.id } }
          route_ids = stops.collect(&:route_id).uniq
        else
          stops = @planning.routes.detect{ |r| !r.vehicle_usage }.stops
          route_ids = stops.any? ? [stops[0].route_id] : []
        end
        raise ActiveRecord::RecordNotFound if stops.empty?

        Planning.transaction do
          stops.each do |stop|
            route = @planning.automatic_insert(stop)
            if route
              route_ids << route.id if route_ids.exclude?(route.id)
            else
              raise Exceptions::LoopError.new
            end
          end

          format.json do
            if @planning.compute && @planning.save! && @planning.reload
              @routes = @planning.routes.select{ |r| route_ids.include? r.id }
              render action: :show
            else
              render json: @planning.errors, status: :unprocessable_entity
            end
          end
        end
      rescue ActiveRecord::RecordNotFound => e
        format.json { render json: { error: t('errors.planning.automatic_insert_no_result') }, status: :unprocessable_entity }
      rescue Exceptions::LoopError => e
        format.json { render json: { error: t('errors.planning.automatic_insert_no_result') }, status: :unprocessable_entity }
      rescue ActiveRecord::RecordInvalid => e
        format.json { render json: @planning.errors, status: :unprocessable_entity }
      end
    end
  end

  def update_stop
    respond_to do |format|
      begin
        Planning.transaction do
          @route = @planning.routes.find{ |route| route.id == Integer(params[:route_id]) }
          @stop = @route.stops.find{ |stop| stop.id == Integer(params[:stop_id]) } if @route
          @stop.assign_attributes(stop_params) if @stop
          if @stop && @route.compute! && @planning.save!
            @routes = [@route]
            format.json { render action: 'show', location: @planning }
          else
            format.json { render json: @planning.errors, status: :unprocessable_entity }
          end
        end
      rescue ActiveRecord::RecordInvalid => e
        format.json { render json: @planning.errors, status: :unprocessable_entity }
      end
    end
  end

  def optimize
    global = ValueToBoolean::value_to_boolean(params[:global])
    active_only = ValueToBoolean::value_to_boolean(params[:active_only])
    respond_to do |format|
      begin
        if Optimizer.optimize(@planning, nil, global, false, active_only) && @planning.customer.save
          format.json { render action: 'show', location: @planning }
        else
          format.json { render json: @planning.errors, status: :unprocessable_entity }
        end
      rescue NoSolutionFoundError
        @planning.errors[:base] = I18n.t('plannings.edit.dialog.optimizer.no_solution')
        format.json { render json: @planning.errors, status: :unprocessable_entity }
      end
    end
  end

  def optimize_route
    active_only = ValueToBoolean::value_to_boolean(params[:active_only])
    respond_to do |format|
      route = @planning.routes.find{ |route| route.id == Integer(params[:route_id]) }
      begin
        if route && Optimizer.optimize(@planning, route, false, false, active_only) && @planning.customer.save
          @routes = [route]
          format.json { render action: 'show', location: @planning }
        else
          format.json { render json: @planning.errors, status: :unprocessable_entity }
        end
      rescue NoSolutionFoundError
        @planning.errors[:base] = I18n.t('plannings.edit.dialog.optimizer.no_solution')
        format.json { render json: @planning.errors, status: :unprocessable_entity }
      end
    end
  end

  def active
    route = @planning.routes.find{ |route| route.id == Integer(params[:route_id]) }
    respond_to do |format|
      if route && route.active(params[:active].to_s.to_sym) && route.compute! && @planning.save
        @routes = [route]
        format.json { render action: 'show', location: @planning }
      else
        format.json { render json: @planning.errors, status: :unprocessable_entity }
      end
    end
  end

  def duplicate
    respond_to do |format|
      @planning = @planning.duplicate
      @planning.save!(validate: false)
      format.html { redirect_to edit_planning_path(@planning), notice: t('activerecord.successful.messages.updated', model: @planning.class.model_name.human) }
    end
  end

  def reverse_order
    route = @planning.routes.find{ |route| route.id == Integer(params[:route_id]) }
    respond_to do |format|
      if route && route.reverse_order && route.compute! && @planning.save
        @routes = [route]
        format.json { render action: 'show', location: @planning }
      else
        format.json { render json: @planning.errors, status: :unprocessable_entity }
      end
    end
  end

  def apply_zonings
    Route.includes_destinations.scoping do
      @planning.zonings = params[:planning] && planning_params[:zoning_ids] ? current_user.customer.zonings.find(planning_params[:zoning_ids]) : []
      @planning.zoning_outdated = true
      @planning.compute
      if @planning.save && @planning.reload
        respond_to do |format|
          format.json do
            render action: :show
          end
        end
      else
        respond_to do |format|
          format.json do
            render json: @planning.errors, status: :unprocessable_entity
          end
        end
      end
    end
  end

  def self.manage
    [:edit, :zoning, :export, :organize, :vehicle, :destination, :store]
  end

  private

  # Use callbacks to share common setup or constraints between actions.
  def set_planning
    @manage_planning = PlanningsController.manage
    @with_stops = ValueToBoolean.value_to_boolean(params[:with_stops], true)

    @planning = current_user.customer.plannings.find(params[:id] || params[:planning_id])
  end

  def includes_destinations
    # FIXME: use new scoping for route_id/route_ids
    if @with_stops && ([:show, :edit, :optimize].exclude?(action_name.to_sym) || !request.format.html?) && !params[:route_id] && !params[:route_ids]
      Route.includes_destinations.scoping do
        yield
      end
    else
      yield
    end
  end

  def check_no_existing_job
    raise Exceptions::JobInProgressError if Job.on_planning(@planning.customer.job_optimizer, @planning.id)
  end

  def planning_params
    p = params.require(:planning).permit(:name, :ref, :active, :date, :begin_date, :end_date, :vehicle_usage_set_id, :tag_operation, tag_ids: [], zoning_ids: [])
    p[:date] = Date.strptime(p[:date], I18n.t('time.formats.datepicker')).strftime(ACTIVE_RECORD_DATE_MASK) unless p[:date].blank?
    p[:begin_date] = Date.strptime(p[:begin_date], I18n.t('time.formats.datepicker')).strftime(ACTIVE_RECORD_DATE_MASK) unless p[:begin_date].blank?
    p[:end_date] = Date.strptime(p[:end_date], I18n.t('time.formats.datepicker')).strftime(ACTIVE_RECORD_DATE_MASK) unless p[:end_date].blank?
    p
  end

  def stop_params
    params.require(:stop).permit(:active)
  end

  def filename
    if @planning
      export_filename @planning, @planning.ref
    else
      I18n.t('plannings.menu.plannings') + '_' + I18n.l(Time.now, format: :datepicker)
    end
  end

  def export_columns
    [
      :ref_planning,
      :planning,
      :route,
      :vehicle,
      :order,
      :stop_type,
      :active,
      :wait_time,
      :time,
      :distance,
      :drive_time,
      :out_of_window,
      :out_of_capacity,
      :out_of_drive_time,
      :status,
      :eta,

      :ref,
      :name,
      :street,
      :detail,
      :postalcode,
      :city,
    ] + ((@customer || @planning.customer).with_state? ? [:state] : []) + [
      :country,
      :lat,
      :lng,
      :comment,
      :phone_number,
      :tags,

      :ref_visit,
      :duration,
      :open1,
      :close1,
      :open2,
      :close2,
      :tags_visit
    ] + ((@customer || @planning.customer).enable_orders ?
      [:orders] :
      (@customer || @planning.customer).deliverable_units.map{ |du|
        ('quantity' + (du.label ? '[' + du.label + ']' : '')).to_sym
      })
  end

  def capabilities
    @isochrone = [[@planning.vehicle_usage_set, Zoning.new.isochrone?(@planning.vehicle_usage_set, false)]]
    @isodistance = [[@planning.vehicle_usage_set, Zoning.new.isodistance?(@planning.vehicle_usage_set, false)]]
  end

  def format_csv(format)
    format.excel do
      @columns = (@params[:columns] && @params[:columns].split('|')) || export_columns
      data = render_to_string.gsub("\n", "\r\n")
      send_data Iconv.iconv('ISO-8859-1//translit//ignore', 'utf-8', data).join(''),
      type: 'text/csv',
      filename: filename + '.csv'
    end
    format.csv do
      @columns = (@params[:columns] && @params[:columns].split('|')) || export_columns
      response.headers['Content-Disposition'] = 'attachment; filename="' + filename + '.csv"'
    end
  end
end
