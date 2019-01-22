require 'test_helper'

class TagTest < ActiveSupport::TestCase

  setup do
    @customer = customers(:customer_one)
  end

  test 'should not save' do
    tag = @customer.tags.build
    assert_not tag.save, 'Saved without required fields'
  end

  test 'should not save with invalid ref' do
    tag = @customer.tags.build(ref: 'test/test')
    assert_not tag.save, 'Saved with bad ref fields'
  end

  test 'should not save color' do
    tag = @customer.tags.build(label: 'plop', color: 'red')
    assert_not tag.save, 'Saved with invalid color'
  end

  test 'should save' do
    tag = @customer.tags.build(label: 'plop', color: '#ff0000', icon: 'fa-diamond')
    assert tag.save
  end

  test 'two tags from same customer couldnt have same label' do
    @customer.tags.build(label: 'foo').save!
    tag2 = @customer.tags.build(label: 'foo')

    refute tag2.valid?
  end
end
