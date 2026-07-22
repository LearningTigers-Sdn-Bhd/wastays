# frozen_string_literal: true

# Test env runs Rails.cache as :null_store (see config/environments/test.rb),
# which never actually caches — so bugs where a cache isn't busted correctly
# stay invisible to specs unless a real cache backend is swapped in for the
# duration of the example.
module RealCacheStore
  def with_real_cache_store
    original_cache = Rails.cache
    Rails.cache = ActiveSupport::Cache::MemoryStore.new
    yield
  ensure
    Rails.cache = original_cache
  end
end

RSpec.configure do |config|
  config.include RealCacheStore
end
