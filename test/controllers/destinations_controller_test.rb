require 'test_helper'

class DestinationsControllerTest < ActionController::TestCase

  setup do
    @request.env['reseller'] = resellers(:reseller_one)
    @destination = destinations(:destination_one)
    sign_in users(:user_one)
  end

  def around
    Routers::RouterWrapper.stub_any_instance(:compute_batch, lambda { |url, mode, dimension, segments, options| segments.collect{ |i| [1000, 60, '_ibE_seK_seK_seK'] } } ) do
      yield
    end
  end

  test 'user can only view destinations from its customer' do
    ability = Ability.new(users(:user_one))
    assert ability.can? :manage, @destination
    ability = Ability.new(users(:user_three))
    assert ability.cannot? :manage, @destination

    get :edit, id: destinations(:destination_four)
    assert_response :not_found
  end

  test 'should get index' do
    get :index
    assert_response :success
    assert_not_nil assigns(:destinations)
    assert_valid response
  end

  test 'should get index in excel' do
    customers(:customer_one).update enable_orders: false
    visits(:visit_one).update quantities: {2 => 2.5}
    get :index, format: :excel
    assert_response :success
    assert_not_nil assigns(:destinations)
    assert_equal "b;destination_one;Rue des Lilas;MyString;33200;Bordeau;;49.1857;-0.3735;;;MyString;MyString;\"\";\"\";b;00:05:33;10:00;11:00;;;tag1;2.5;\r".encode("iso-8859-1"), response.body.split("\n").find{ |l| l.start_with? 'b;destination_one' }
  end

  test 'should get index in excel with order array' do
    get :index, format: :excel
    assert_response :success
    assert_not_nil assigns(:destinations)
    assert_equal "b;destination_one;Rue des Lilas;MyString;33200;Bordeau;;49.1857;-0.3735;;;MyString;MyString;\"\";\"\";b;00:05:33;10:00;11:00;;;tag1\r".encode("iso-8859-1"), response.body.split("\n").find{ |l| l.start_with? 'b;destination_one' }
  end

  test 'should get new' do
    get :new
    assert_response :success
    assert_valid response
  end

  test 'should create destination without visit' do
    assert_no_difference('Stop.count') do
      assert_difference('Destination.count') do
        assert_no_difference('Visit.count') do
          post :create, destination: {
            city: @destination.city,
            lat: @destination.lat,
            lng: @destination.lng,
            name: @destination.name,
            postalcode: @destination.postalcode,
            street: @destination.street,
            state: @destination.state,
            detail: @destination.detail,
            comment: @destination.comment,
            phone_number: @destination.phone_number
          }
        end
      end
    end

    assert_redirected_to edit_destination_path(assigns(:destination))
  end

  test 'should create destination with visit' do
    assert_difference('Stop.count', 1) do
      assert_difference('Destination.count', 1) do
        assert_difference('Visit.count', 1) do
          post :create, destination: {
            city: 'Bordeaux',
            name: 'new dest',
            postalcode: '33000',
            state: 'Aquitaine',
            comment: 'comment',
            phone_number: '+336123456789',
            visits_attributes: [{
              open1: '10:00',
              close1: '18:00',
              open2: '20:00',
              close2: '21:00',
              quantity1_1: '10',
              tag_ids: [tags(:tag_one).id]
            }]
          }
        end
      end
    end

    assert_redirected_to edit_destination_path(assigns(:destination))
  end

  test 'should create destination with visit exceeding one day' do
    assert_difference('Destination.count', 1) do
      assert_difference('Visit.count', 1) do
        post :create, destination: {
            city: 'Bordeaux',
            name: 'new dest',
            postalcode: '33000',
            state: 'Aquitaine',
            comment: 'comment',
            phone_number: '+336123456789',
            visits_attributes: {'1' => {
                open1: '18:00',
                close1: '06:00',
                close1_day: '1',
                open2: '10:00',
                open2_day: '1',
                close2: '14:00',
                close2_day: '1'
            }}
        }
      end
    end
    assert_redirected_to edit_destination_path(assigns(:destination))

    assert_difference('Destination.count', 1) do
      assert_difference('Visit.count', 1) do
        post :create, destination: {
            city: 'Bordeaux',
            name: 'new dest',
            postalcode: '33000',
            state: 'Aquitaine',
            comment: 'comment',
            phone_number: '+336123456789',
            visits_attributes: [{
                                    open1: '18:00',
                                    close1: '06:00',
                                    close1_day: '1',
                                    open2: '10:00',
                                    open2_day: '1',
                                    close2: '14:00',
                                    close2_day: '1'
                                }]
        }
      end
    end
    assert_redirected_to edit_destination_path(assigns(:destination))
  end

  test 'should create destination and touch planning' do
    d = Planning.find_by(name: 'planning1')
    d.tags = []
    d.save!
    assert_difference('Stop.count', 1) do
      assert_difference('Destination.count', 1) do
        assert_difference('Visit.count', 1) do
          post :create, destination: {
            city: 'Bordeaux',
            name: 'new dest',
            postalcode: '33000',
            comment: 'comment',
            phone_number: '+336123456789',
            visits_attributes: [{
              open1: '10:00',
              close1: '18:00',
              open2: '20:00',
              close2: '21:00',
              quantity1_1: '10'
            }]
          }
        end
      end
    end

    assert_redirected_to edit_destination_path(assigns(:destination))
  end

  test 'should not create destination' do
    assert_difference('Destination.count', 0) do
      post :create, destination: { name: '' }
    end

    assert_template :new
    destination = assigns(:destination)
    assert destination.errors.any?
    assert_valid response
  end

  test 'should get edit' do
    get :edit, id: @destination
    assert_response :success
    assert_valid response
  end

  test 'should update destination' do
    patch :update, id: @destination, destination: { city: @destination.city, lat: @destination.lat, lng: @destination.lng, name: @destination.name, postalcode: @destination.postalcode, street: @destination.street, state: @destination.state, detail: @destination.detail, comment: @destination.comment, phone_number: @destination.phone_number }
    assert_redirected_to edit_destination_path(assigns(:destination))
  end

  test 'should update destination and visit' do
    size_visits = @destination.visits.size
    visits_attributes = Hash[@destination.visits.map{ |v| [v.id.to_s, v.attributes.merge(quantities: {'1' => 1, '2' => 2.3})]}]
    patch :update, id: @destination, destination: { visits_attributes: visits_attributes}
    assert_redirected_to edit_destination_path(assigns(:destination))
    assert_equal [[1, 2.3]] * size_visits, @destination.reload.visits.map{ |v| v.quantities.values }
  end

  test 'should update destination with geocode error' do
    Mapotempo::Application.config.geocode_geocoder.class.stub_any_instance(:code, lambda{ |*a| raise GeocodeError.new }) do
      patch :update, id: @destination, destination: { city: 'Nantes', lat: nil, lng: nil }
      assert_redirected_to edit_destination_path(assigns(:destination))
      assert_not_nil flash[:warning]
    end
  end

  test 'should update destination tags' do
    patch :update, id: @destination, destination: { tag_ids: [tags(:tag_two).id] }
    assert_redirected_to edit_destination_path(assigns(:destination))
  end

  test 'should not update destination' do
    patch :update, id: @destination, destination: { name: '' }

    assert_template :edit
    destination = assigns(:destination)
    assert destination.errors.any?
    assert_valid response
  end

  test 'should destroy destination' do
    assert_difference('Destination.count', -1) do
      delete :destroy, id: @destination
    end

    assert_redirected_to destinations_path
  end

  test 'should clear' do
    delete :clear
    assert_redirected_to destinations_path
  end

  test 'should show import template' do
    [:csv, :excel].each{ |format|
      get :import_template, format: format
      assert_response :success
    }
  end

  test 'should import' do
    users(:user_one).customer.update advanced_options: "{\"import\": {\"destinations\": {\"spreadsheetColumnsDef\": {\"route\": \"my_route\"}}}}"
    get :import
    assert_response :success
    assert_valid response
    assert_equal 'my_route', assigns(:columns_default)['route']
  end

  test 'should upload' do
    file = ActionDispatch::Http::UploadedFile.new({
      tempfile: File.new(Rails.root.join('test/fixtures/files/import_destinations_one.csv')),
    })
    file.original_filename = 'import_destinations_one.csv'

    destinations_count = @destination.customer.destinations.count
    plannings_count = @destination.customer.plannings.select{ |planning| planning.tags_compatible? [tags(:tag_one)] }.count
    import_count = 1
    import_rest_count = @destination.customer.vehicle_usage_sets[0].vehicle_usages.select{ |v| v.active && v.rest_duration && v.rest_start && v.rest_stop }.size

    assert_difference('Destination.count') do
      assert_difference('Stop.count', (destinations_count + import_count + import_rest_count) + import_count * plannings_count) do
        assert_difference('Planning.count') do
          post :upload_csv, import_csv: { replace: false, file: file }
        end
      end
    end

    assert_redirected_to destinations_path
  end

  test 'should not upload' do
    file = ActionDispatch::Http::UploadedFile.new({
      tempfile: File.new(Rails.root.join('test/fixtures/files/import_invalid.csv')),
    })
    file.original_filename = 'import_invalid.csv'

    assert_difference('Destination.count', 0) do
      post :upload_csv, import_csv: { replace: false, file: file }
    end

    assert_template :import
    assert_valid response
  end

  test 'should display an error' do
    file = ActionDispatch::Http::UploadedFile.new({
      tempfile: File.new(Rails.root.join('test/fixtures/files/import_malformed.csv')),
    })
    file.original_filename = 'import_malformed.csv'

    assert_difference('Destination.count', 0) do
      post :upload_csv, import_csv: { replace: false, file: file }
    end

    assert_template :import
    assert_valid response
  end
end
