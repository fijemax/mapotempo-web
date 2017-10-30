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
class ApiV01 < Grape::API
  version '0.1', using: :path

  content_type :json, 'application/json; charset=UTF-8'
  content_type :geojson, 'application/vnd.geo+json; charset=UTF-8'
  content_type :xml, 'application/xml'

  # As rails utils 'status()' works with Fixnum, we need to set a special formatter for XML object
  xml_custom_formatter = ->(object, env) {
    object.is_a?(Integer) ? object.to_s : object.to_xml
  }

  formatter :xml, xml_custom_formatter

  default_format :json

  mount V01::Api

  add_swagger_documentation(
    base_path: '/api',
    hide_documentation_path: true,
    consumes: [
      'application/json; charset=UTF-8',
      'application/xml',
    ],
    produces: [
      'application/json; charset=UTF-8',
      'application/vnd.geo+json; charset=UTF-8',
      'application/xml',
    ],
    doc_version: nil,
    info: {
      title: 'API',
      contact_email: Mapotempo::Application.config.api_contact_email,
      contact_url: Mapotempo::Application.config.api_contact_url,
      license: 'GNU Affero General Public License 3',
      license_url: 'https://raw.githubusercontent.com/Mapotempo/mapotempo-web/master/LICENSE',
      description: '
[Simplified view of domain model](' + Mapotempo::Application.config.swagger_docs_base_path + '/api/0.1/Model-simpel.svg).
## Model
Model is structured around four majors concepts: the Customer account, Destinations, Vehicles and Plannings.
* `Customers`: many of objects are linked to a customer account (relating to the user calling API).
The customer has many users, each user has his own `api_key`.
* `Destinations`: location points to visit with constraints. The same `Destination` can be visited several times : in this case several `Visit`s are associated to one `Destination`.
* `Vehicles`: vehicles definition are splited in two parts:
 * the structural definition named `Vehicle` (car, truck, bike, consumption, etc.)
 * and the vehicle usage `VehicleUsage`, a specific usage of a physical vehicle in a specific context. Vehicles can be used in many contexts called `VehicleUsageSet` (set of all vehicles usages under a context). Multiple values are only available if dedicated option for customer is active. For instance, if customer needs to use its vehicle 2 times per day (morning and evening), he needs 2 `VehicleUsageSet` called "Morning" and "Evening" : each can have different values defined for stores, rest, etc... `VehicleUsageSet` defines default values for vehicle usage.
* `Plannings`: `Planning` is a set of `Route`s to `Visit` `Destination`s with `Vehicle` within a `VehicleUsageSet` context.
A route is a track between all destinations reached by a vehicle (a new route is created for each customer\'s vehicle and a route without vehicle is created for all out-of-route destinations). By default all customer\'s visites are used in a planning.

## Technical access
### Swagger descriptor
This REST API is described with Swagger. The Swagger descriptor defines the request end-points, the parameters and the return values. The API can be addressed by HTTP request or with a generated client using the Swagger descriptor.
### API key
All access to the API are subject to an `api_key` parameter in order to authenticate the user.
This parameter can be sent with a query string on each available operation: `https://app.mapotempo.com/api/0.1/{objects}?api_key={your_personal_api_key}`
### Return
The API supports several return formats: `json` and `xml` which depend of the requested extension used in url.
### I18n
Functionnal textual returns are subject to translation and depend of HTTP header `Accept-Language`. HTTP error codes are not translated.
## Admin acces
Using an admin `api_key` switches to advanced opperations (on `Customer`, `User`, `Vehicle`, `Profile`). Most of operations from the current api are usable either for normal user `api_key` or admin user `api_key` (not both).
## More concepts
When a customer is created some objects are created by default with this new customer:
* `Vehicle`: multiple, depending of the `max_vehicles` defined for customer
* `DeliverableUnit`: one default
* `VehicleUsageSet`: one default
* `VehicleUsage`: multiple, depending of the vehicles number
* `Store`: one default

### Profiles, Layers, Routers
`Profile` is a concept which allows to set several parameters for the customer:
* `Layer`: which allows to choose the background map
* `Router`: which allows to build route\'s information.

Several default profiles are available and can be listed with an admin `api_key`.

### Tags
`Tag` is a concept to filter visits and create planning only for a subset of visits. For instance, if some visits are tagged "Monday", it allows to create a new planning for "Monday" tag and use only dedicated visits.
### Zonings
`Zoning` is a concept which allows to define multiple `Zone`s (areas) around destinatons. A `Zone` can be affected to a `Vehicle` and if it is used into a `Planning`, all `Destinations` inside areas will be affected to the zone\'s vehicle (or `Route`). A polygon defining a `Zone` can be created outside the application or can be automatically generated from a planning.

## Code samples
* Create and display destinations or visits.
Here some samples for these operations: [using PHP](' + Mapotempo::Application.config.swagger_docs_base_path + '/api/0.1/examples/php/example.php), [using Ruby](' + Mapotempo::Application.config.swagger_docs_base_path + '/api/0.1/examples/ruby/example.rb).
Note you can import destinations/visits and create a planning at the same time if you know beforehand the route for each destination/visit.
* Same operations are available for stores (note you have an existing default store).
* With created destinations/visits, you can create a planning (routes and stops are automatically created depending of yours vehicles and destinations/visits)
* In existing planning, you have availability to move stops (which represent visits) on a dedicated route (which represent a dedicated vehicle).
* With many unaffected (out-of-route) stops in a planning, you may create a zoning to move many stops in several routes. Create a zoning (you can generate zones in this zoning automatically from automatic clustering), if you apply zoning (containing zones linked to a vehicle) on your planning, all stops contained in different zones will be moved in dedicated routes.
'})
end
