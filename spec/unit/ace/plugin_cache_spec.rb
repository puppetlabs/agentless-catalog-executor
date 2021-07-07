# frozen_string_literal: true

require 'ace/plugin_cache'
require 'ace/puppet_util'
require 'hocon'

RSpec.describe ACE::PluginCache do
  let(:plugin_cache) { described_class.new('/tmp/environment_cache') }

  let(:puppetserver_directory_path) { '/foo/' }
  let(:fake_file_path) { 'fake_file.rb' }
  let(:params) {
    '?checksum_type=sha256&environment=production&ignore=.hg&links=follow&max_files=-1&recurse=true&source_permissions='
  }

  before do
    allow(ACE::ForkUtil).to receive(:isolate).and_yield
  end

  describe '#expire' do
    before do
      allow(Dir).to receive(:glob).with('foo/environment_cache/*').and_return(['foo/environment_cache/production',
                                                                               'foo/environment_cache/bar'])
      allow(File).to receive(:directory?).with('foo/environment_cache/production').and_return(true)
      allow(File).to receive(:directory?).with('foo/environment_cache/bar').and_return(true)
      allow(File).to receive(:mtime).with('foo/environment_cache/bar').and_return(Time.now)
    end

    it 'removes only directories which have expired' do
      allow(File).to receive(:mtime).with('foo/environment_cache/production').and_return(Time.now -
                                                                                    (ACE::PluginCache::PURGE_TTL + 100))

      allow(FileUtils).to receive(:remove_dir)
      described_class.new('foo/environment_cache', purge_interval: 1)
      sleep 1
      expect(FileUtils).to have_received(:remove_dir).with('foo/environment_cache/production').at_most(2).times
      expect(FileUtils).not_to have_received(:remove_dir).with('foo/environment_cache/bar')
    end

    it 'does not remove directories when nothing expired' do
      allow(File).to receive(:mtime).with('foo/environment_cache/production').and_return(Time.now)
      allow(FileUtils).to receive(:remove_dir)
      described_class.new('foo/environment_cache')
      expect(FileUtils).not_to have_received(:remove_dir)
    end
  end

  context 'with a mock filesystem' do
    before do
      allow(FileUtils).to receive(:mkdir_p)
      allow(FileUtils).to receive(:cp_r)
      allow(FileUtils).to receive(:touch)
      allow(FileUtils).to receive(:remove_dir)
      allow(ACE::PuppetUtil).to receive(:isolated_puppet_settings)
    end

    describe '#setup' do
      it { expect(plugin_cache.setup).to be_a(described_class) }

      it "creates the cache-dir" do
        plugin_cache.setup
        expect(FileUtils).to have_received(:mkdir_p).with('/tmp/environment_cache')
      end
    end

    describe '#with_synced_libdir' do
      it 'isolates the call and yields' do
        allow(plugin_cache).to receive(:with_synced_libdir_core).and_yield

        expect { |b| plugin_cache.with_synced_libdir('environment', false, 'certname', &b) }.to yield_with_no_args
        expect(ACE::ForkUtil).to have_received(:isolate).ordered
        expect(plugin_cache).to have_received(:with_synced_libdir_core).with('environment').ordered
      end
    end
  end

  describe '#sync_core' do
    # work around for executing a semi realistic pluginsync
    # the ca, crls, keys and certs are just used to pass parsing
    # that occurs in puppet
    before do
      allow(Puppet::Pops::Loaders).to receive(:new)
      ACE::PuppetUtil.init_global_settings('spec/fixtures/ssl/ca.pem',
                                           'spec/fixtures/ssl/crl.pem',
                                           'spec/fixtures/ssl/key.pem',
                                           'spec/fixtures/ssl/cert.pem',
                                           '/tmp/environment_cache',
                                           URI.parse('https://localhost:9999'))
      FileUtils.mkdir_p('/tmp/environment_cache/production')
      ACE::PuppetUtil.isolated_puppet_settings('foo', 'production', false, '/tmp/environment_cache/production')
    end
    # This example is a ugly tradeoff between more confidence in calling the
    # Puppet::Configurer::PluginHandler.new.download_plugins methods and having
    # simpler tests. Since we do not have good control or understanding of the
    # Puppet API, we opt for the former.

    it 'calls into the puppetserver to download plugins' do
      stub_request(:get, "https://localhost:9999/puppet/v3/file_metadatas/pluginfacts#{params}use")
        .to_return(
          status: 200,
          body: '[
            {
              "path":"/etc/puppetlabs/code/environments/production/modules",
              "relative_path":".","links":"follow","owner":0,"group":0,"mode":493,
              "checksum":{"type":"ctime",
                "value":"{ctime}2019-03-28 10:53:51 +0000"},
                "type":"directory","destination":null
            }
          ]', headers: { content_type: 'application/json' }
        )
      stub_request(:get, "https://localhost:9999/puppet/v3/file_metadata/pluginfacts")
        .to_return(status: 200, body: '{
          "message":"Not Found: Could not find file_metadata pluginfacts",
          "issue_kind":"RESOURCE_NOT_FOUND"
          }', headers: { content_type: 'application/json' })
      stub_request(:get, "https://localhost:9999/puppet/v3/file_metadatas/plugins#{params}ignore")
        .to_return(status: 200, body: "[
         {
           \"path\":\"#{puppetserver_directory_path}\",
           \"relative_path\":\".\",\"links\":\"follow\",
           \"owner\":999,\"group\":999,\"mode\":420,
           \"checksum\":{\"type\":\"ctime\",
           \"value\":\"{ctime}2019-03-28 10:53:51 +0000\"},\"type\":\"directory\",\"destination\":null
         },
         {
           \"path\":\"#{puppetserver_directory_path}\",
           \"relative_path\":\"#{fake_file_path}\",\"links\":\"follow\",
           \"owner\":999,\"group\":999,\"mode\":420,
           \"checksum\":{\"type\":\"md5\",
           \"value\":\"{md5}acbd18db4cc2f85cedef654fccc4a4d8\"},\"type\":\"file\",\"destination\":null
          }
         ]", headers: { content_type: 'application/json' })
      stub_request(:get, "https://localhost:9999/puppet/v3/file_metadata/plugins")
        .to_return(status: 200, body: "{
          \"path\":\"#{fake_file_path}\",
          \"relative_path\":null,\"links\":\"follow\",
          \"owner\":999,\"group\":999,\"mode\":420,
          \"checksum\":{\"type\":\"md5\",
          \"value\":\"{md5}acbd18db4cc2f85cedef654fccc4a4d8\"
          },\"type\":\"file\",\"destination\":null}", headers: { content_type: 'application/json' })
      stub_request(:get, "https://localhost:9999/puppet/v3/file_content/plugins/fake_file.rb?environment=production")
        .to_return(status: 200, body: "foo", headers: {})

      expect(ACE::ForkUtil).not_to have_received(:isolate)

      result = plugin_cache.sync_core('production')
      folder_size = Dir[File.join(result, '**', '*')].count { |file| File.file?(file) }
      expect(folder_size).to eq 1
      expect(result).to be_a(String)
    end

    context 'when do_purge is false' do
      let(:plugin_cache) { described_class.new('/tmp/environment_cache', do_purge: false) }

      it 'will not set up purge timer' do
        expect(plugin_cache.instance_variable_get(:@purge)).to be_nil
      end
    end

    context 'when do_purge is true' do
      let(:plugin_cache) { described_class.new('/tmp/environment_cache', do_purge: true) }

      it 'will create and run the purge timer' do
        expect(plugin_cache.instance_variable_get(:@purge)).to be_a(Concurrent::TimerTask)
      end
    end

    context 'when do_purge is true and cache_dir_mutex is specified' do
      let(:other_mutex) { spy('other_mutex') } # rubocop:disable RSpec/VerifiedDoubles
      let(:plugin_cache) do
        described_class.new('/tmp/environment_cache',
                            purge_interval: 1,
                            purge_timeout: 1,
                            purge_ttl: 1,
                            cache_dir_mutex: other_mutex,
                            do_purge: true)
      end

      it 'will create and run the purge timer' do
        expect(plugin_cache.instance_variable_get(:@purge)).to be_a(Concurrent::TimerTask)
        expect(plugin_cache.instance_variable_get(:@cache_dir_mutex)).to eq(other_mutex)

        plugin_cache
        sleep 2 # allow time for the purge timer to fire
        expect(other_mutex).to have_received(:with_write_lock).at_least(:once)
      end
    end
  end

  describe '#with_synced_libdir_core' do
    before do
      allow(FileUtils).to receive(:remove_dir)
    end

    it 'calls remove_dir after yielding' do
      allow(plugin_cache).to receive(:sync_core).with('production').and_return('/tmp/foo/blah/plugins')
      expect(ACE::ForkUtil).not_to have_received(:isolate)
      expect { |b| plugin_cache.with_synced_libdir_core('production', &b) }.to yield_with_no_args
      expect(FileUtils).to have_received(:remove_dir).with('/tmp/foo/blah/plugins')
    end
  end
end
