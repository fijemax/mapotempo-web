# Copyright © Mapotempo, 2015
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
require 'exceptions'

class V01::Stops < Grape::API
  helpers SharedParams
  helpers do
    # Never trust parameters from the scary internet, only allow the white list through.
    def stop_params
      p = ActionController::Parameters.new(params)
      p.permit(:active)
    end
  end

  resource :plannings do
    params do
      requires :planning_id, type: Integer
    end
    segment '/:planning_id' do

      resource :routes do
        params do
          requires :route_id, type: Integer
        end
        segment '/:route_id' do

          resource :stops do
            desc 'Fetch stop.',
              nickname: 'getStop',
              success: V01::Entities::Route
            params do
              requires :id, type: Integer
            end
            get ':id' do
              s = current_customer.plannings.where(ParseIdsRefs.read(params[:planning_id])).first!.routes.where(ParseIdsRefs.read(params[:route_id])).first!.stops.where(id: params[:id]).first!
              present s, with: V01::Entities::Stop
            end

            desc 'Update stop activation.',
              nickname: 'updateStop'
            params do
              requires :id, type: Integer
              use :params_from_entity, entity: V01::Entities::Stop.documentation.slice(:active)
            end
            put ':id' do
              planning = current_customer.plannings.where(ParseIdsRefs.read(params[:planning_id])).first!
              raise Exceptions::JobInProgressError if Job.on_planning(current_customer.job_optimizer, planning.id)
              route = planning.routes.find{ |route| route.id == Integer(params[:route_id]) } || raise(ActiveRecord::RecordNotFound.new)
              stop = route.stops.find{ |stop| stop.id == Integer(params[:id]) } || raise(ActiveRecord::RecordNotFound.new)
              Planning.transaction do
                stop.update! stop_params
                route.save!
                route.compute && planning.save!
                status 204
              end
            end

            desc 'Move stop position in routes.',
              # FIXME: Unit test succeeds in move stop from route in another...
              detail: 'Set a new #N position for a stop in route which was in a previous #M position in the same route.',
              nickname: 'moveStop'
            params do
              requires :id, type: Integer, desc: 'Stop id to move'
              requires :index, type: Integer, desc: 'New position in the route'
            end
            patch ':id/move/:index' do
              planning = current_customer.plannings.where(ParseIdsRefs.read(params[:planning_id])).first!
              raise Exceptions::JobInProgressError if Job.on_planning(current_customer.job_optimizer, planning.id)
              stop = nil
              # FIXME: raise RecordNotFound for route and stop
              planning.routes.find{ |route| stop = route.stops.find{ |stop| stop.id == Integer(params[:id]) } }
              Planning.transaction do
                if planning.move_stop(planning.routes.find{ |route| route.id == Integer(params[:route_id]) }, stop, Integer(params[:index])) && planning.compute && planning.save!
                  status 204
                else
                  status 400
                end
              end
            end
          end
        end
      end
    end
  end
end
