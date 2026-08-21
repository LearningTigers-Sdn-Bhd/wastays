# This file is copied to spec/ when you run 'rails generate rspec:install'
require 'spec_helper'
ENV['RAILS_ENV'] ||= 'test'
require_relative '../config/environment'
# Prevent database truncation if the environment is production
abort("The Rails environment is running in production mode!") if Rails.env.production?
# Uncomment the line below in case you have `--require rails_helper` in the `.rspec` file
# that will avoid rails generators crashing because migrations haven't been run yet
# return unless Rails.env.test?
require 'rspec/rails'
require 'capybara/cuprite'
require 'webmock/rspec'
require 'view_component/test_helpers'
require 'view_component/system_test_helpers'
require 'test_prof/recipes/rspec/let_it_be'
WebMock.disable_net_connect!(allow_localhost: true)
# Add additional requires below this line. Rails is not loaded until this point!

# Requires supporting ruby files with custom matchers and macros, etc, in
# spec/support/ and its subdirectories. Files matching `spec/**/*_spec.rb` are
# run as spec files by default. This means that files in spec/support that end
# in _spec.rb will both be required and run as specs, causing the specs to be
# run twice. It is recommended that you do not name files matching this glob to
# end with _spec.rb. You can configure this pattern with the --pattern
# option on the command line or in ~/.rspec, .rspec or `.rspec-local`.
#
# The following line is provided for convenience purposes. It has the downside
# of increasing the boot-up time by auto-requiring all files in the support
# directory. Alternatively, in the individual `*_spec.rb` files, manually
# require only the support files necessary.
#
# Rails.root.glob('spec/support/**/*.rb').sort_by(&:to_s).each { |f| require f }
Dir[Rails.root.join('spec', 'support', '**', '*.rb')].each { |f| require f }

# Ensures that the test database schema matches the current schema file.
# If there are pending migrations it will invoke `db:test:prepare` to
# recreate the test database by loading the schema.
# If you are not using ActiveRecord, you can remove these lines.
begin
  ActiveRecord::Migration.maintain_test_schema!
rescue ActiveRecord::PendingMigrationError => e
  abort e.to_s.strip
end
RSpec.configure do |config|
  config.define_derived_metadata(file_path: %r{/spec/migrations/}) do |metadata|
    metadata[:migration] = true
  end

  # The live concierge eval spends real money against a real provider, so it
  # runs only when asked for by name. Everything else -- bin/test, bin/ci --
  # never sees it.
  config.filter_run_excluding(:live_llm) unless ENV["CONCIERGE_LIVE"]

  # webmock/rspec resets before every example, so the hole has to be reopened
  # per example, and only for the three hosts a concierge turn can legitimately
  # reach.
  config.before(:each, :live_llm) do
    WebMock.disable_net_connect!(
      allow_localhost: true,
      allow: %w[api.openai.com api.anthropic.com generativelanguage.googleapis.com]
    )
  end

  config.around(:each, :migration) do |example|
    previous_verbose = ActiveRecord::Migration.verbose
    ActiveRecord::Migration.verbose = false
    example.run
  ensure
    ActiveRecord::Migration.verbose = previous_verbose
  end

  # Remove this line if you're not using ActiveRecord or ActiveRecord fixtures
  config.fixture_paths = [
    Rails.root.join('spec/fixtures')
  ]

  config.include FactoryBot::Syntax::Methods
  config.include ActiveSupport::Testing::TimeHelpers
  config.include ViewComponent::TestHelpers, type: :component
  config.include ViewComponent::SystemTestHelpers, type: :component
  config.include Capybara::RSpecMatchers, type: :component

  # If you're not using ActiveRecord, or you'd prefer not to run each of your
  # examples within a transaction, remove the following line or assign false
  # instead of true.
  config.use_transactional_fixtures = true

  # You can uncomment this line to turn off ActiveRecord support entirely.
  # config.use_active_record = false

  # RSpec Rails uses metadata to mix in different behaviours to your tests,
  # for example enabling you to call `get` and `post` in request specs. e.g.:
  #
  #     RSpec.describe UsersController, type: :request do
  #       # ...
  #     end
  #
  # The different available types are documented in the features, such as in
  # https://rspec.info/features/8-0/rspec-rails
  #
  # You can also infer these behaviours automatically by location, e.g.
  # /spec/models would pull in the same behaviour as `type: :model` but this
  # behaviour is considered legacy and will be removed in a future version.
  #
  # To enable this behaviour uncomment the line below.
  # config.infer_spec_type_from_file_location!

  # Filter lines from Rails gems in backtraces.
  config.filter_rails_from_backtrace!
  # arbitrary gems may also be filtered via:
  # config.filter_gems_from_backtrace("gem name")

  config.before(:each, type: :system) do
    driven_by :cuprite
    unless chrome_available?
      skip "Skipping system test: Chrome executable not detected in supported Linux/macOS locations."
    end
  end

  config.after(:each) do
    travel_back
  end

  # cuprite clears cookies on session reset but not sessionStorage/localStorage,
  # so stay-view persists scroll + focus state (keyed by a board query that
  # repeats across examples) leaks into later examples. Clear web storage after
  # each system example to keep them isolated.
  config.after(:each, type: :system) do
    page.execute_script("window.sessionStorage.clear(); window.localStorage.clear();")
  rescue StandardError
    # The page may be on about:blank or storage may be unavailable — nothing to clear.
  end
end

def chrome_available?
  return true if system("google-chrome --version > /dev/null 2>&1")
  return true if system("google-chrome-stable --version > /dev/null 2>&1")

  File.executable?("/Applications/Google Chrome.app/Contents/MacOS/Google Chrome")
end

def chrome_binary_path
  return "google-chrome" if system("google-chrome --version > /dev/null 2>&1")
  return "google-chrome-stable" if system("google-chrome-stable --version > /dev/null 2>&1")

  mac_chrome = "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"
  return mac_chrome if File.executable?(mac_chrome)

  nil
end

Capybara.default_max_wait_time = 10

Capybara.register_driver :cuprite do |app|
  browser_path = chrome_binary_path

  Capybara::Cuprite::Driver.new(
    app,
    browser_path: browser_path,
    browser_options: {
      "no-sandbox" => nil,
      "disable-dev-shm-usage" => nil,
      "disable-gpu" => nil,
      "disable-site-isolation-trials" => nil,
      "disable-features" => "site-per-process"
    },
    headless: true,
    timeout: 60,
    process_timeout: 120,
    pending_connection_errors: false,
    url_blacklist: %w[
      fonts.googleapis.com
      fonts.gstatic.com
    ]
  )
end

Shoulda::Matchers.configure do |config|
  config.integrate do |with|
    with.test_framework :rspec
    with.library :rails
  end
end
