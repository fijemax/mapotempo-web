CSV.generate({col_sep: ';'}) { |csv|
  csv << [
    I18n.t('vehicles.import.ref_vehicle'),
    I18n.t('vehicles.import.name_vehicle'),
    I18n.t('vehicles.import.contact_email'),
    I18n.t('vehicles.import.emission'),
    I18n.t('vehicles.import.consumption')
  ] +
    @vehicle_usage_set.customer.deliverable_units.map { |du|
      I18n.t('vehicles.import.capacities') + (du.label ? '[' + du.label + ']' : '')
    } +
  [
    I18n.t('vehicles.import.router_mode'),
    I18n.t('vehicles.import.router_dimension'),
    I18n.t('vehicles.import.router_options'),
    I18n.t('vehicles.import.speed_multiplicator'),
    I18n.t('vehicles.import.color'),
    I18n.t('vehicles.import.devices'),

    I18n.t('vehicle_usage_sets.import.open'),
    I18n.t('vehicle_usage_sets.import.close'),
    I18n.t('vehicle_usage_sets.import.store_start_ref'),
    I18n.t('vehicle_usage_sets.import.store_stop_ref'),
    I18n.t('vehicle_usage_sets.import.rest_start'),
    I18n.t('vehicle_usage_sets.import.rest_stop'),
    I18n.t('vehicle_usage_sets.import.rest_duration'),
    I18n.t('vehicle_usage_sets.import.store_rest_ref'),
    I18n.t('vehicle_usage_sets.import.service_time_start'),
    I18n.t('vehicle_usage_sets.import.service_time_end')
  ]

  device_keys = {}
  Mapotempo::Application.config.devices.to_h.each { |device_name, device_object|
      if device_object.respond_to?('definition')
        device_definition = device_object.definition
        if device_definition.key?(:forms) && device_definition[:forms].key?(:vehicle)
          device_keys[device_name] = device_definition[:forms][:vehicle].keys
        end
      end
  }

  @vehicle_usage_set.vehicle_usages.each { |vehicle_usage|
    vehicle_columns = [
      vehicle_usage.vehicle.ref,
      vehicle_usage.vehicle.name,
      vehicle_usage.vehicle.contact_email,
      vehicle_usage.vehicle.emission,
      vehicle_usage.vehicle.consumption,
    ] +
    @vehicle_usage_set.customer.deliverable_units.map { |du|
      vehicle_usage.vehicle.capacities[du.id]
    } +
    [
      vehicle_usage.vehicle.router.try(:mode),
      vehicle_usage.vehicle.router_dimension,
      vehicle_usage.vehicle.router_options.to_json,
      vehicle_usage.vehicle.speed_multiplicator,
      vehicle_usage.vehicle.color
    ]

    enabled_devices = {}
    @vehicle_usage_set.customer.device.enableds.keys.each { |device_key|
      enabled_devices.merge!(vehicle_usage.vehicle.devices.slice(*device_keys[device_key]))
    }
    vehicle_columns << enabled_devices.select { |key, value| !value.to_s.empty? }.to_json

    vehicle_usage_columns = [
      vehicle_usage.default_open_absolute_time,
      vehicle_usage.default_close_absolute_time,
      vehicle_usage.default_store_start.try(:ref),
      vehicle_usage.default_store_stop.try(:ref),
      vehicle_usage.default_rest_start_absolute_time,
      vehicle_usage.default_rest_stop_absolute_time,
      vehicle_usage.default_rest_duration_time,
      vehicle_usage.default_store_rest.try(:ref),
      vehicle_usage.default_service_time_start,
      vehicle_usage.default_service_time_end
    ]

    csv << vehicle_columns + vehicle_usage_columns
  }
}
