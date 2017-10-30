# Copyright © Mapotempo, 2013-2017
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
class Job < Struct
  def before(job)
    @job = job
  end

  def job_progress_save(progress)
    # Job is executed inside a transaction (for instance to be sure data are all updated in database when job is deleted)
    # New thread will use a new connection outside this transaction to update job progress
    Thread.new do
      @job.progress = progress
      @job.save
    end.join
  end

  def self.on_planning(job, planning_id)
    if job && job.handler
      match = job.handler.match(/planning_id: ([0-9]+)/)
      !match || match[1].to_i == planning_id
    end
  end
end
