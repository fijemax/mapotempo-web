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

include PlanningIcalendar
include IcalendarUrlHelper

# Specific file to get plannings because it needs to return specific content types (js, xml and ics)
class V01::PlanningsGet < Grape::API
  content_type :json, 'application/javascript'
  content_type :geojson, 'application/vnd.geo+json'
  content_type :xml, 'application/xml'
  content_type :ics, 'text/calendar'
  default_format :json

  helpers do
    ID_DESC = 'ID or REF ref:[value]'.freeze

    def get_format_routes_email(planning_ids)
      hash = current_customer.vehicles.select(&:contact_email).group_by(&:contact_email)
      struct = hash.each{ |email, vehicles|
        hash[email] = vehicles.map{ |v| {
          vehicle: v,
          routes: v.vehicle_usages.flat_map{ |vu|
            vu.routes.select{ |r|
              planning_ids.include?(r.planning_id)
            }.map{ |r| {
              url: api_route_calendar_path(r, api_key: @current_user.api_key),
              route: r
            }}
          }
        }
      }}
    end
  end

  resource :plannings do
    desc 'Fetch customer\'s plannings.',
      nickname: 'getPlannings',
      success: V01::Entities::Planning
    params do
      optional :ids, type: Array[String], desc: 'Select returned plannings by id separated with comma. You can specify ref (not containing comma) instead of id, in this case you have to add "ref:" before each ref, e.g. ref:ref1,ref:ref2,ref:ref3.', coerce_with: CoerceArrayString
      optional :begin_date, type: Date, desc: 'Select only plannings after this date.'
      optional :end_date, type: Date, desc: 'Select only plannings before this date.'
      optional :active, type: Boolean, desc: 'Select only active plannings.'
      optional :tags, type: Array[String], coerce_with: ->(c) { c.split(',') }, desc: 'Select plannings which contains at least one of these tags label'
      optional :geojson, type: Symbol, values: [:true, :false, :point, :polyline], default: :false, desc: 'Fill the geojson field with route geometry: `point` to return only points, `polyline` to return with encoded linestring.'
    end
    get do
      plannings = current_customer.plannings

      plannings = plannings.where(active: params[:active]) unless params[:active].nil?

      if params[:begin_date] || params[:end_date]
        plannings = if params[:begin_date] && params[:end_date]
                      plannings.where('begin_date >= ? AND end_date <= ?', params[:begin_date], params[:end_date])
                    elsif params[:end_date]
                      plannings.where('end_date <= ?', params[:end_date])
                    elsif params[:begin_date]
                      plannings.where('begin_date >= ?', params[:begin_date])
                    end
      end

      plannings = plannings.joins(:tags).where(tags: {label: params[:tags]}).reorder('tags.id') if params[:tags]

      plannings = plannings.select{ |plan| params[:ids].any?{ |s| ParseIdsRefs.match(s, plan) } } if params.key?(:ids)
      if env['api.format'] == :ics
        if params.key?(:email) && YAML.load(params[:email])
          planning_ids = plannings.map(&:id)
          emails_routes = get_format_routes_email(planning_ids)
          route_calendar_email(emails_routes)
          status 204
        else
          plannings_calendar(plannings).to_ical
        end
      else
        present plannings, with: V01::Entities::Planning, geojson: params[:geojson]
      end
    end

    desc 'Fetch planning.',
      nickname: 'getPlanning',
      success: V01::Entities::Planning
    params do
      requires :id, type: String, desc: ID_DESC
      optional :geojson, type: Symbol, values: [:true, :false, :point, :polyline], default: :false, desc: 'Fill the geojson field with route geometry, when using json output. For geojson output, param can be only set to `point` to return only points, `polyline` to return with encoded linestring.'
      optional :quantities, type: Boolean, default: false, desc: 'Include the quantities when using geojson output.'
      optional :stores, type: Boolean, default: false, desc: 'Include the stores in geojson output.'
    end
    get ':id' do
      planning = current_customer.plannings.where(ParseIdsRefs.read(params[:id])).first!
      if env['api.format'] == :ics
        if params.key?(:email)
          emails_routes = get_format_routes_email([planning.id])
          route_calendar_email(emails_routes)
          status 204
        else
          planning_calendar(planning).to_ical
        end
      elsif env['api.format'] == :geojson
        planning.to_geojson(
          params[:stores],
          true,
          if params[:geojson] == :polyline
            :polyline
          elsif params[:geojson] == :point
            false
          else
            true
          end,
          params[:quantities]
        )
      else
        present planning, with: V01::Entities::Planning, geojson: params[:geojson]
      end
    end
  end
end
