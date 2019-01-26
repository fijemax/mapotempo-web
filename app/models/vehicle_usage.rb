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
class VehicleUsage < ApplicationRecord
  default_scope { order(:id) }

  belongs_to :vehicle_usage_set

  belongs_to :vehicle
  belongs_to :store_start, class_name: 'Store', inverse_of: :vehicle_usage_starts
  belongs_to :store_stop, class_name: 'Store', inverse_of: :vehicle_usage_stops
  belongs_to :store_rest, class_name: 'Store', inverse_of: :vehicle_usage_rests
  has_many :routes, inverse_of: :vehicle_usage, autosave: true

  has_and_belongs_to_many :tags, autosave: true, after_add: :update_tags_track, after_remove: :update_tags_track

  accepts_nested_attributes_for :vehicle, update_only: true

  nilify_blanks

  include TimeAttr
  attribute :open, ScheduleType.new
  attribute :close, ScheduleType.new
  attribute :rest_start, ScheduleType.new
  attribute :rest_stop, ScheduleType.new
  attribute :rest_duration, ScheduleType.new
  attribute :service_time_start, ScheduleType.new
  attribute :service_time_end, ScheduleType.new
  attribute :work_time, ScheduleType.new
  time_attr :open, :close, :rest_start, :rest_stop, :rest_duration, :service_time_start, :service_time_end, :work_time

  validate :close_after_open
  validate :rest_stop_after_rest_start
  validate :rest_duration_range
  validate :work_time_inside_window

  before_update :update_outdated

  before_save :update_routes

  include Consistency
  validate_consistency :tags, attr_consistency_method: ->(vehicle_usage) { vehicle_usage.vehicle.try(:customer_id) }

  after_save -> { @tag_ids_changed = false }

  before_destroy :update_stops

  scope :active, ->{ where(active: true) }
  scope :for_customer_id, ->(customer_id) { joins(:vehicle_usage_set).where(vehicle_usage_sets: { customer_id: customer_id }) }
  scope :with_stores, -> { includes(:store_start, :store_stop, :store_rest) }

  amoeba do
    exclude_association :routes

    customize(lambda { |_original, copy|
      def copy.update_outdated; end

      def copy.update_routes; end
    })
  end

  def default_open
    open || vehicle_usage_set.open
  end

  def default_open_time
    open_time || vehicle_usage_set.open_time
  end

  def default_open_absolute_time
    open_absolute_time || vehicle_usage_set.open_absolute_time
  end

  def default_close
    close || vehicle_usage_set.close
  end

  def default_close_time
    close_time || vehicle_usage_set.close_time
  end

  def default_close_absolute_time
    close_absolute_time || vehicle_usage_set.close_absolute_time
  end

  def default_store_start
    store_start || vehicle_usage_set.store_start
  end

  def default_store_start_time
    store_start_time || vehicle_usage_set.store_start_time
  end

  def default_store_start_absolute_time
    store_start_absolute_time || vehicle_usage_set.store_start_absolute_time
  end

  def default_store_stop
    store_stop || vehicle_usage_set.store_stop
  end

  def default_store_stop_time
    store_stop_time || vehicle_usage_set.store_stop_time
  end

  def default_store_stop_absolute_time
    store_stop_absolute_time || vehicle_usage_set.store_stop_absolute_time
  end

  def default_store_rest
    store_rest || vehicle_usage_set.store_rest
  end

  def default_store_rest_time
    store_rest_time || vehicle_usage_set.store_rest_time
  end

  def default_rest_start
    rest_start || vehicle_usage_set.rest_start
  end

  def default_rest_start_time
    rest_start_time || vehicle_usage_set.rest_start_time
  end

  def default_rest_start_absolute_time
    rest_start_absolute_time || vehicle_usage_set.rest_start_absolute_time
  end

  def default_rest_stop
    rest_stop || vehicle_usage_set.rest_stop
  end

  def default_rest_stop_time
    rest_stop_time || vehicle_usage_set.rest_stop_time
  end

  def default_rest_stop_absolute_time
    rest_stop_absolute_time || vehicle_usage_set.rest_stop_absolute_time
  end

  def default_rest_duration
    rest_duration || vehicle_usage_set.rest_duration
  end

  def default_rest_duration_time
    rest_duration_time || vehicle_usage_set.rest_duration_time
  end

  def default_rest_duration_time_with_seconds
    rest_duration_time_with_seconds || vehicle_usage_set.rest_duration_time_with_seconds
  end

  def default_rest_duration?
    !default_rest_duration.nil?
  end

  def default_service_time_start
    service_time_start || vehicle_usage_set.service_time_start
  end

  def default_service_time_start_time
    service_time_start_time || vehicle_usage_set.service_time_start_time
  end

  def default_service_time_end
    service_time_end || vehicle_usage_set.service_time_end
  end

  def default_service_time_end_time
    service_time_end_time || vehicle_usage_set.service_time_end_time
  end

  def default_work_time(with_service = false)
    default = work_time || vehicle_usage_set.work_time

    if with_service && default
      default = default - (default_service_time_start || 0) - (default_service_time_end || 0)
    end

    return default
  end

  def default_work_time_time
    work_time_time || vehicle_usage_set.work_time_time
  end

  def outside_default_work_time?(start_time, current_time)
    default_work_time ? current_time - default_rest_duration.to_i > start_time + default_work_time : false
  end

  def work_or_window_time
    ChronicDuration.output(default_work_time || (default_close - default_open), limit_to_hours: true, format: :chrono, units: 5)
  end

  def update_rest
    if default_rest_duration.nil?
      # No more rest
      routes.each(&:remove_rests)
    else
      # New or changed rest
      routes.each(&:add_or_update_rest)
    end
  end

  def update_tags_track(_tag)
    @tag_ids_changed = true
  end

  # Used by validate_consistency
  def tag_ids_changed?
    @tag_ids_changed
  end

  def changed?
    tag_ids_changed? || super
  end

  def quantities(planning)
    hash = []
    planning.routes.find{ |route|
      route.vehicle_usage == self
    }.quantities.select{ |_k, value| value > 0 }.each do |id, value|
      unit = planning.customer.deliverable_units.find{ |du| du.id == id }
      next unless unit
      hash << {
        deliverable_unit_id: unit.id,
        label: unit.label,
        unit_icon: unit.default_icon,
        quantity: value
      }
    end
    hash
  end

  private

  def update_routes
    return if changes.exclude?(:active)
    if active?
      vehicle_usage_set.plannings.each do |planning|
        planning.vehicle_usage_add self
        planning.save!
      end
    else
      vehicle_usage_set.plannings.each do |planning|
        planning.vehicle_usage_remove self
        planning.save!
      end
    end
  end

  def update_outdated
    if rest_duration_changed?
      update_rest
    end

    if open_changed? || close_changed? || store_start_id_changed? || store_stop_id_changed? || rest_start_changed? || rest_stop_changed? || rest_duration_changed? || store_rest_id_changed? || service_time_start_changed? || service_time_end_changed? || work_time_changed?
      routes.each{ |route|
        route.outdated = true
      }
    end
  end

  def update_stops
    vehicle_usage_set.plannings.each do |planning|
      planning.vehicle_usage_remove self
      planning.save!
    end
    routes.destroy_all
  end

  def close_after_open
    if self.default_open.present? && self.default_close.present? && self.default_close <= self.default_open
      errors.add(:close, I18n.t('activerecord.errors.models.vehicle_usage.attributes.close.after'))
    end
  end

  def rest_stop_after_rest_start
    if self.rest_stop.present? && ((self.rest_start.present? && self.rest_stop < self.rest_start) || !self.rest_start.present?)
      errors.add(:rest_stop, I18n.t('activerecord.errors.models.vehicle_usage.attributes.rest_stop.after'))
    end
  end

  def rest_duration_range
    errors.add(:rest_start, I18n.t('activerecord.errors.models.vehicle_usage.missing_rest_window')) if self.default_rest_duration && self.default_rest_start.nil?
    errors.add(:rest_stop, I18n.t('activerecord.errors.models.vehicle_usage.missing_rest_window')) if self.default_rest_duration && self.default_rest_stop.nil?
    errors.add(:rest_duration, I18n.t('activerecord.errors.models.vehicle_usage.missing_rest_duration')) if self.default_rest_duration.nil? && (self.default_rest_start || self.default_rest_stop)

    open_duration = self.default_open || 0
    service_time_start_duration = self.default_service_time_start || 0
    close_duration = self.default_close || 0
    service_time_end_duration = self.default_service_time_end || 0

    working_day_start = open_duration + service_time_start_duration
    working_day_end = close_duration - service_time_end_duration

    if (close_duration - open_duration) <= service_time_start_duration && service_time_start_duration > 0
      errors.add(:service_time_start, I18n.t('activerecord.errors.models.vehicle_usage.service_range'))
    elsif (close_duration - open_duration) <= service_time_end_duration && service_time_start_duration > 0
      errors.add(:service_time_end, I18n.t('activerecord.errors.models.vehicle_usage.service_range'))
    elsif (close_duration - open_duration) <= (service_time_start_duration + service_time_end_duration) && service_time_start_duration + service_time_end_duration > 0
      errors.add(:base, "#{I18n.t('activerecord.attributes.vehicle_usage.service_time_start')} / #{I18n.t('activerecord.attributes.vehicle_usage.service_time_end')} #{I18n.t('activerecord.errors.models.vehicle_usage.service_range')}")
    elsif self.default_rest_start && self.default_rest_stop
      if !(self.default_rest_start >= working_day_start) || !(self.default_rest_stop <= working_day_end)
        begin_day = (working_day_start / 86400).to_i
        end_day = (working_day_end / 86400).to_i
        errors.add(:base, I18n.t('activerecord.errors.models.vehicle_usage.rest_range', start: Time.at(working_day_start).utc.strftime('%H:%M') + (begin_day > 0 ? " (+#{begin_day})" : ''), end: Time.at(working_day_end).utc.strftime('%H:%M') + (end_day > 0 ? " (+#{end_day})" : '')))
      end
    end
  end

  def work_time_inside_window
    if self.work_time.present? && self.default_open.present? && self.default_close.present? && self.work_time > (self.default_close - self.default_open) - ((self.default_service_time_start || 0) + (self.default_service_time_end || 0))
      errors.add(:work_time, I18n.t('activerecord.errors.models.vehicle_usage.work_time_inside_window'))
    end
  end
end
