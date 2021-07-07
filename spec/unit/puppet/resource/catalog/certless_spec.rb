# frozen_string_literal: true

require 'spec_helper'
require 'puppet'
require 'puppet/resource/catalog'
require 'puppet/indirector/rest'
require 'puppet/indirector/catalog/certless'
require 'puppet/http/response'

RSpec.describe Puppet::Resource::Catalog::Certless do
  let(:indirector) { described_class.new }

  let(:request) { instance_double(Puppet::Indirector::Request, 'request') }
  let(:session) { instance_double(Puppet::HTTP::Session, 'session') }
  let(:compiler) { instance_double(Puppet::HTTP::Service::Compiler, 'compiler') }
  let(:environment) { instance_double(Puppet::Node::Environment::Remote, 'environment') }

  let(:request_options) do
    {
      transport_facts: {
        clientcert: "foo.delivery.puppetlabs.net",
        clientversion: "6.4.0",
        clientnoop: false
      },
      trusted_facts: {
        authenticated: "remote",
        extensions: {},
        certname: "foo.delivery.puppetlabs.net",
        hostname: "foo",
        domain: "delivery.puppetlabs.net"
      },
      fail_on_404: true,
      transaction_uuid: "2078748407702309438222210184383400900",
      job_id: "271036342116034393375846637943780463672"
    }
  end

  let(:certname) { 'foo.delivery.puppetlabs.net' }
  let(:persistence) { { facts: true, catalog: true } }
  let(:facts) {
    {
      clientcert: 'foo.delivery.puppetlabs.net',
      clientnoop: false,
      clientversion: '6.4.0'
    }
  }

  let(:trusted_facts) {
    {
      authenticated: 'remote',
      certname: 'foo.delivery.puppetlabs.net',
      domain: 'delivery.puppetlabs.net',
      extensions: {},
      hostname: 'foo'
    }
  }

  let(:opts) {
    {
      persistence: persistence,
      environment: environment.name,
      facts: facts,
      trusted_facts: trusted_facts,
      transaction_uuid: '2078748407702309438222210184383400900',
      job_id: '271036342116034393375846637943780463672',
      options: {
        prefer_requested_environment: false,
        capture_logs: false
      }
    }
  }

  let(:uri) { URI.parse('https://www.example.com') }

  describe '#find' do
    before do
      allow(request).to receive(:key).and_return('foo.delivery.puppetlabs.net')
      allow(request).to receive(:environment).and_return(environment)
      allow(request).to receive(:options).and_return(request_options)
      allow(request).to receive(:server).and_return('localhost')
      allow(request).to receive(:port).and_return('9999')
      allow(environment).to receive(:name).and_return('environment')

      allow(Puppet).to receive(:lookup).with(:http_session).and_return(session)
      allow(session).to receive(:route_to).with(:puppet).and_return(compiler)
    end

    it 'returns a Puppet Catalog on success' do
      expected_post4_args = [certname, opts]
      mocked_post4_return = [nil, Puppet::Resource::Catalog.new('foo.delivery.puppetlabs.net'), []]

      allow(compiler).to receive(:post_catalog4)
        .with(*expected_post4_args)
        .and_return(mocked_post4_return)

      expect(indirector.find(request)).to be_a Puppet::Resource::Catalog

      expect(compiler).to have_received(:post_catalog4)
        .with(*expected_post4_args)
    end

    it 'raises error on a 404' do
      allow(request).to receive(:options).and_return(request_options)

      # need a Net::HTTP response
      stub_request(:post, 'https://www.example.com')
        .to_return(status: 404, headers: { "Content-Type" => 'application/json' })
      http_response = Net::HTTP.post(uri, '')
      puppet_http_response = Puppet::HTTP::ResponseNetHTTP.new(uri, http_response)

      allow(compiler).to receive(:post_catalog4).and_raise(Puppet::HTTP::ResponseError.new(puppet_http_response))

      expect { indirector.find(request) }.to raise_error(Puppet::Error, /resulted in 404 with the message/)

      expect(compiler).to have_received(:post_catalog4)
    end
  end
end
