# Copyright © Mapotempo, 2018
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

class V01::VisitsByTags < Grape::API

  helpers SharedParams

  resource :visits_by_tags do
    desc 'Get visit with corresponding tag id or tag ref',
      nickname: 'VisitsByTags'
    params do
      requires :id, type: String, desc: SharedParams::ID_DESC
    end
    get ':id' do
      destinations = current_customer.destinations.includes_visits
      destinations.reduce([]) { |sum, d|
        sum << d.visits.select { |v|
          v.tags.find { |t| ParseIdsRefs.match(params[:id], t) }
        }
      }.flatten
    end
  end
end
