if Job.on_planning(@planning.customer.job_optimizer, @planning.id)
  json.optimizer do
    json.extract! @planning.customer.job_optimizer, :id, :progress, :attempts
    json.error !!@planning.customer.job_optimizer.failed_at
    json.customer_id @planning.customer.id
    json.dispatch_params_delayed_job do
      json.with_stops @with_stops
      json.route_ids @routes.map(&:id).join(',') if @routes
    end
  end
else
  json.prefered_unit current_user.prefered_unit
  json.extract! @planning, :id, :ref
  json.customer_id @planning.customer.id
  json.customer_enable_external_callback current_user.customer.enable_external_callback
  json.customer_external_callback_name current_user.customer.external_callback_name
  json.customer_external_callback_url current_user.customer.external_callback_url
  duration = @planning.routes.includes_vehicle_usages.select(&:vehicle_usage).to_a.sum(0){ |route| route.end && route.start ? route.end - route.start : 0 }
  json.duration '%i:%02i' % [duration / 60 / 60, duration / 60 % 60]
  json.distance locale_distance(@planning.routes.to_a.sum(0){ |route| route.distance || 0 }, current_user.prefered_unit)
  json.emission number_to_human(@planning.routes.to_a.sum(0){ |route| route.emission || 0 }, precision: 4)
  (json.outdated true) if @planning.outdated
  json.size @planning.routes.to_a.sum(0){ |route| route.stops.size }
  json.size_active @planning.routes.to_a.sum(0){ |route| route.vehicle_usage ? route.size_active : 0 }
  json.stores (@planning.vehicle_usage_set.vehicle_usages.collect(&:default_store_start) + @planning.vehicle_usage_set.vehicle_usages.collect(&:default_store_stop) + @planning.vehicle_usage_set.vehicle_usages.collect(&:default_store_rest)).compact.uniq do |store|
    json.extract! store, :id, :name, :street, :postalcode, :city, :country, :lat, :lng, :color, :icon, :icon_size
  end
  json.routes (@routes || (@with_stops ? @planning.routes.includes_destinations : @planning.routes)), partial: 'routes/edit', as: :route
end
