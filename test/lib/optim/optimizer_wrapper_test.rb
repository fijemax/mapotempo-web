require 'test_helper'

require 'optim/optimizer_wrapper'

class OptimizerWrapperTest < ActionController::TestCase
  setup do
    @optim = OptimizerWrapper.new(ActiveSupport::Cache::NullStore.new, 'http://localhost:1791/0.1', 'demo')

    uri_template = Addressable::Template.new('http://localhost:1791/0.1/vrp/submit.json')
    @stub_VrpSubmit = stub_request(:post, uri_template).to_return(status: 200, body: File.new(File.expand_path('../../../', __FILE__) + '/fixtures/optimizer-wrapper/vrp-submit.json').read)

    uri_template = Addressable::Template.new('http://localhost:1791/0.1/vrp/jobs/{job_id}.json?api_key={api_key}')
    @stub_VrpJob = stub_request(:get, uri_template).to_return(status: 200, body: File.new(File.expand_path('../../../', __FILE__) + '/fixtures/optimizer-wrapper/vrp-job.json').read)
  end

  def teardown
    remove_request_stub(@stub_VrpJob)
    remove_request_stub(@stub_VrpSubmit)
  end

  test 'shoud optimize' do
    p = [[1, 1], [2, 2], [3, 3], [4, 4], [5, 5], [6, 6]]
    t = [
      {start1: nil, end1: nil, start2: nil, end2: nil, duration: 300.0, stop_id: 1, quantities: {}},
      {start1: nil, end1: nil, start2: nil, end2: nil, duration: 300.0, stop_id: 2, quantities: {}},
      {start1: 28800, end1: 36000, start2: nil, end2: nil, duration: 500.0, stop_id: 3},
      {start1: 0, end1: 7200, start2: nil, end2: nil, duration: 300.0, stop_id: 4},
    ]
    r = [
      {start1: 28800, end1: 36000, duration: 500.0, stop_id: 5},
    ]

    assert_equal [[], [1, 2, 3, 4, 5]], @optim.optimize(p, t, [id: 1, stores: [:start, :stop], rests: r, router: routers(:router_one), capacities: {}], optimize_minimal_time: 3)

    assert_equal [[], [1, 2, 3, 4, 5]], @optim.optimize(p, t, [id: 1, stores: [:start], rests: r, router: routers(:router_one)], optimize_minimal_time: 3)

    assert_equal [[], [1, 2, 3, 4, 5]], @optim.optimize(p, t, [id: 1, stores: [], rests: r, router: routers(:router_one)], optimize_minimal_time: 3)
  end
end
