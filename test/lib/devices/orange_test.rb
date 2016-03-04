require 'test_helper'

class OrangeTest < ActionController::TestCase

  require Rails.root.join("test/lib/devices/orange_base")
  include OrangeBase

  setup do
    @customer = add_orange_credentials customers(:customer_one)
    @service = Mapotempo::Application.config.devices.orange
    @service.set_params customer: @customer
  end

  test 'test list' do
    with_stubs [:auth] do
      assert @service.test_list user: @customer.orange_user, password: @customer.orange_password
    end
  end

  test 'list devices' do
    with_stubs [:get_vehicles] do
      assert @service.list_devices
    end
  end

  test 'send route' do
    with_stubs [:send] do
      set_route
      assert_nothing_raised do
        @service.send_route route: @route
      end
    end
  end

  test 'clear route' do
    with_stubs [:send] do
      set_route
      assert_nothing_raised do
        @service.clear_route route: @route
      end
    end
  end

  test 'get vehicles positions' do
    with_stubs [:vehicles_pos] do
      assert @service.get_vehicles_pos
    end
  end

end