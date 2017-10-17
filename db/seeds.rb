I18n.locale = :fr

mapnik_fr = Layer.create!(source: "osm", name: "Mapnik-fr", url: "http://tile-{s}.openstreetmap.fr/osmfr/{z}/{x}/{y}.png", urlssl: "https://{s}.tile.openstreetmap.fr/osmfr/{z}/{x}/{y}.png", attribution: "Tiles by OpenStreetMap-France")
mapnik = Layer.create!(source: "osm", name: "Mapnik", url: "http://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png", urlssl: "https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png", attribution: "Tiles by OpenStreetMap")
mapbox = Layer.create!(source: "osm", name: "MapBox Street", url: "http://{s}.tiles.mapbox.com/v3/examples.map-i87786ca/{z}/{x}/{y}.png", urlssl: "https://{s}.tiles.mapbox.com/v3/examples.map-i87786ca/{z}/{x}/{y}.png", attribution: "Tiles by MapBox")
stamen_bw = Layer.create!(source: "osm", name: "Stamen B&W", name_locale: {fr: "Stamen N&B"}, url: "http://{s}.tile.stamen.com/toner-lite/{z}/{x}/{y}.png", urlssl: "https://stamen-tiles-{s}.a.ssl.fastly.net/toner-lite/{z}/{x}/{y}.png", attribution: "Tiles by Stamen Design")

here_layer = Layer.create!(source: "here", name: "Here", url: "http://4.base.maps.cit.api.here.com/maptile/2.1/maptile/newest/normal.day/{z}/{x}/{y}/256/png8?app_id=YOUR_APP_ID&app_code=YOUR_APP_CODE", urlssl: "https://4.base.maps.cit.api.here.com/maptile/2.1/maptile/newest/normal.day/{z}/{x}/{y}/256/png8?app_id=YOUR_APP_ID&app_code=YOUR_APP_CODE", attribution: "Here")

# Routers
car = RouterWrapper.create!(
    mode: 'car',
    name: 'RouterWrapper-Car',
    name_locale: {fr: 'Calculateur pour voiture', en: 'Car router'},
    url_time: 'http://localhost:9090',
    options: {time: true, distance: true, avoid_zones: false, isochrone: true, isodistance: true, approach: true, track: true, motorway: true})
car_urban = RouterWrapper.create!(
    mode: 'car_urban',
    name: 'RouterWrapper-Car-Urban',
    name_locale: {fr: 'Calculateur pour voiture urbaine', en: 'Urban car router'},
    url_time: 'http://localhost:9090',
    options: {time: true, distance: true, avoid_zones: false, isochrone: true, isodistance: true, approach: true, track: true, motorway: true})
bicycle = RouterWrapper.create!(
    mode: 'bicycle',
    name: 'RouterWrapper-Bicycle',
    name_locale: {fr: 'Calculateur pour vélo', en: 'Bicycle router'},
    url_time: 'http://localhost:9090',
    options: {time: true, distance: true, avoid_zones: false, isochrone: true, isodistance: true})
pedestrian = RouterWrapper.create!(
    mode: 'pedestrian',
    name: 'RouterWrapper-Pedestrian',
    name_locale: {fr: 'Calculateur pour piéton', en: 'Pedestrian router'},
    url_time: 'http://localhost:9090',
    options: {time: true, distance: true, avoid_zones: false, isochrone: true, isodistance: true})
truck = RouterWrapper.create!(
    mode: 'truck',
    name: 'RouterWrapper-HereTruck',
    name_locale: {fr: 'Calculateur pour camion', en: 'Truck router'},
    url_time: 'http://localhost:9090',
    options: {time: true, distance: false, avoid_zones: true, isochrone: false, isodistance: false, motorway: true, toll: true, trailers: true, weight: true, weight_per_axle: true, height: true, width: true, length: true, hazardous_goods: true, strict_restriction: true})
public_transport = RouterWrapper.create!(
    mode: 'public_transport',
    name: 'RouterWrapper-PublicTransport',
    name_locale: {fr: 'Calculateur pour transport en commun', en: 'Public Transport router'},
    url_time: 'http://localhost:9090',
    options: {time: true, distance: false, avoid_zones: false, isochrone: true, isodistance: true, max_walk_distance: true})

profile_all = Profile.create!(name: "All", layers: [mapnik_fr, mapnik, mapbox, stamen_bw, here_layer], routers: [car, car_urban, bicycle, pedestrian, truck, public_transport])

reseller = Reseller.create!(host: "localhost:3000", name: "Mapotempo")
customer = Customer.create!(reseller: reseller, name: "Toto", default_country: "France", router: car, profile: profile_all, test: true, max_vehicles: 2)
admin = User.create!(email: "admin@example.com", password: "123456789", reseller: reseller, layer: mapnik)
test = User.create!(email: "test@example.com", password: "123456789", layer: mapnik, customer: customer)
toto = User.create!(email: "toto@example.com", password: "123456789", layer: mapnik, customer: customer)

Tag.create!(label: "lundi", customer: customer)
Tag.create!(label: "jeudi", customer: customer)
frigo = Tag.create!(label: "frigo", customer: customer)

Visit.create!(ref: 'v1', quantities: {customer.deliverable_units[0].id => 1}, destination: Destination.create!(name: "l1", street: "Place Picard", postalcode: "33000", city: "Bordeaux", lat: 44.84512, lng: -0.578, customer: customer))
Visit.create!(ref: 'v2', destination: Destination.create!(name: "l2", street: "Rue Esprit des Lois", postalcode: "33000", city: "Bordeaux", lat: 44.83395, lng: -0.56545, customer: customer))
Visit.create!(ref: 'v3', destination: Destination.create!(name: "l3", street: "Rue de Nuits", postalcode: "33000", city: "Bordeaux", lat: 44.84272, lng: -0.55013, customer: customer))
destination_4 = Destination.create!(name: "l4", street: "Rue de New York", postalcode: "33000", city: "Bordeaux", lat: 44.86576, lng: -0.57577, customer: customer)
Visit.create!(ref: 'v4-1', quantities: {customer.deliverable_units[0].id => 0.5}, destination: destination_4, tags: [frigo])
Visit.create!(ref: 'v4-2', quantities: {customer.deliverable_units[0].id => 0.5}, destination: destination_4)
