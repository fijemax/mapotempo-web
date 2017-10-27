require 'test_helper'

class VisitTest < ActiveSupport::TestCase

  test 'should not save' do
    visit = Visit.new
    assert_not visit.save, 'Saved without required fields'
  end

  test 'should update add tag' do
    destination = destinations(:destination_one)
    stops(:stop_three_one).destroy
    assert_difference('Stop.count', destination.customer.plannings.select{ |planning| planning.tags.include?(tags(:tag_two)) }.count) do
      destination.visits[0].tags << tags(:tag_two)
      destination.save!
      destination.customer.save!
    end
  end

  test 'should update remove tag' do
    destination = destinations(:destination_one)
    stops(:stop_three_one).destroy
    assert_difference('Stop.count', -1) do
      destination.visits[0].tags = []
      destination.save!
      destination.customer.save!
    end
  end

  test 'should update tag' do
    destination = destinations(:destination_one)
    planing = plannings(:planning_one)
    stops(:stop_three_one).destroy
    planing.tags = [tags(:tag_one), tags(:tag_two)]

    routes(:route_one_one).stops.clear
    destination.visits[0].tags = []

    assert_difference('Stop.count', 0) do
      destination.visits[0].tags = [tags(:tag_one)]
      destination.save!
      destination.customer.save!
    end

    assert_difference('Stop.count', 2) do
      destination.visits[0].tags = [tags(:tag_one), tags(:tag_two)]
      destination.save!
      destination.customer.save!
    end
  end

  test 'should set same start and close' do
    destination = destinations(:destination_one)
    visit = destination.visits[0]
    visit.open1 = visit.close1 = Time.new(2000, 01, 01, 00, 10, 00, '+00:00')
    destination.save!
  end

  test 'should validate open and close time exceeding one day' do
    destination = destinations(:destination_one)
    visit = destination.visits[0]
    visit.update open1: '08:00', close1: '12:00'
    assert visit.valid?
    assert_equal visit.close1, 12 * 3_600
    visit.update open2: '18:00', close2: '32:00'
    assert visit.valid?
    assert_equal visit.close2, 32 * 3_600
  end

  test 'should validate open and close time from different type' do
    destination = destinations(:destination_one)
    visit = destination.visits[0]
    visit.update open1: '08:00', close1: 32 * 3_600
    assert visit.valid?
    assert_equal visit.close1, 32 * 3_600
    visit.update open1: '08:00', close1: '32:00'
    assert visit.valid?
    assert_equal visit.close1, 32 * 3_600
    visit.update open1: '08:00', close1: 115200.0
    assert visit.valid?
    assert_equal visit.close1, 32 * 3_600
    visit.update open1: Time.parse('08:00'), close1: '32:00'
    assert visit.valid?
    assert_equal visit.open1, 8 * 3_600
    visit.update open1: DateTime.parse('2011-01-01 08:00'), close1: '32:00'
    assert visit.valid?
    assert_equal visit.open1, 8 * 3_600
    visit.update open1: 8.hours, close1: '32:00'
    assert visit.valid?
    assert_equal visit.open1, 8 * 3_600

    visit.update open1: '06:00', close1: '07:00'
    visit.update open2: '08:00', close2: 32 * 3_600
    assert visit.valid?
    assert_equal visit.close2, 32 * 3_600
    visit.update open2: '08:00', close2: '32:00'
    assert visit.valid?
    assert_equal visit.close2, 32 * 3_600
    visit.update open2: '08:00', close2: 115200.0
    assert visit.valid?
    assert_equal visit.close2, 32 * 3_600
    visit.update open2: Time.parse('08:00'), close2: '32:00'
    assert visit.valid?
    assert_equal visit.open2, 8 * 3_600
    visit.update open2: DateTime.parse('2011-01-01 08:00'), close2: '32:00'
    assert visit.valid?
    assert_equal visit.open2, 8 * 3_600
    visit.update open2: 8.hours, close2: '32:00'
    assert visit.valid?
    assert_equal visit.open2, 8 * 3_600
  end

  test 'should set invalid TW' do
    destination = destinations(:destination_one)
    visit = destination.visits[0]
    visit.open1 = Time.new(2000, 01, 01, 00, 10, 00, '+00:00')
    visit.close1 = Time.new(2000, 01, 01, 00, 9, 00, '+00:00')
    assert !destination.save

    visit.open1 = Time.new(2000, 01, 01, 00, 10, 00, '+00:00')
    visit.open2 = Time.new(2000, 01, 01, 00, 11, 00, '+00:00')
    assert !destination.save

    visit.open1 = Time.new(2000, 01, 01, 00, 10, 00, '+00:00')
    visit.close1 = Time.new(2000, 01, 01, 00, 11, 00, '+00:00')
    visit.open2 = Time.new(2000, 01, 01, 00, 10, 00, '+00:00')
    assert !destination.save

    visit.open1 = Time.new(2000, 01, 01, 00, 10, 00, '+00:00')
    visit.close1 = Time.new(2000, 01, 01, 00, 11, 00, '+00:00')
    visit.open1 = Time.new(2000, 01, 01, 00, 12, 00, '+00:00')
    visit.close2 = Time.new(2000, 01, 01, 00, 11, 00, '+00:00')
    assert !destination.save
  end

  test 'should support localized number separator' do
    orig_locale = I18n.locale
    visit = visits :visit_one

    begin
      I18n.locale = :en
      assert I18n.locale == :en
      assert_not_nil Visit.localize_numeric_value(nil)
      visit.update! quantities: {1 => nil}
      assert visit.localized_quantities[1].nil? # Don't crash with nil values
      visit.update! quantities: {1 => '10.5'} # Assign with localized separator
      assert_equal 10.5, visit.quantities[1]
      assert_equal '10.5', visit.localized_quantities[1] # Localized value
      visit.update! quantities: {1 => 10}
      assert_equal 10, visit.quantities[1]
      assert_equal '10', visit.localized_quantities[1] # Remove trailing zeros
      visit.update! quantities: {1 => 10.1} # Assign without localized separator
      assert_equal 10.1, visit.quantities[1]
      assert_not_nil Visit.localize_numeric_value(nil)

      I18n.locale = :fr
      assert I18n.locale == :fr
      assert_not_nil Visit.localize_numeric_value(nil)
      visit.update! quantities: {1 => nil}
      assert visit.localized_quantities[1].nil? # Don't crash with nil values
      visit.update! quantities: {1 => '10,5'} # Assign with localized separator
      assert_equal 10.5, visit.quantities[1]
      assert_equal '10,5', visit.localized_quantities[1] # Localized value
      visit.update! quantities: {1 => 10}
      assert_equal 10, visit.quantities[1]
      assert_equal '10', visit.localized_quantities[1] # Remove trailing zeros
      visit.update! quantities: {1 => 10.1} # Assign without localized separator
      assert_equal 10.1, visit.quantities[1]
    ensure
      I18n.locale = orig_locale
    end
  end

  test 'should return color and icon' do
    visit = visits :visit_one
    tag1 = tags :tag_one

    assert_equal tag1.color, visit.color
    assert_nil visit.icon
  end

  test 'should return error if quantity is invalid' do
    visit = visits(:visit_one)

    visit.quantities = {customers(:customer_one).deliverable_units[0].id => '12,3'}
    assert visit.save

    visit.quantities = {customers(:customer_one).deliverable_units[0].id => 'not a float'}
    assert_not visit.save
    assert_equal visit.errors.first.second, I18n.t('activerecord.errors.models.visit.attributes.quantities.not_float')
  end

  test 'should update outdated for quantity' do
    visit = visits :visit_one
    assert_not visit.stop_visits[-1].route.outdated
    visit.quantities = {customers(:customer_one).deliverable_units[0].id => '12,3'}
    visit.save!
    assert visit.stop_visits[-1].route.reload.outdated # Reload route because it not updated in main scope
    assert_equal 12.3, Visit.find(visit.id).quantities[customers(:customer_one).deliverable_units[0].id]
  end

  test 'should update outdated for empty quantity' do
    visit = visits :visit_two
    assert_not visit.stop_visits[-1].route.outdated
    visit.quantities = {}
    visit.save!
    assert visit.stop_visits[-1].route.reload.outdated # Reload route because it not updated in main scope
    assert_nil Visit.find(visit.id).quantities[customers(:customer_one).deliverable_units[0].id]
  end

  test 'should outdate route after tag changed' do
    route = routes(:route_zero_one)
    assert !route.outdated
    visits(:visit_unaffected_one).update tags: [tags(:tag_one), tags(:tag_two)]
    assert route.reload.outdated
  end
end
