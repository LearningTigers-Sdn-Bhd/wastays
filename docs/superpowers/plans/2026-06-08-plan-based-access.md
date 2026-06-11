# Plan-Based (Subscription) Access Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Gate hotel feature access by the hotel's subscribed plan, via an editable plan-template matrix managed by admin.

**Architecture:** Four new tables (`plans`, `feature_groups`, `features`, `plan_features`) mapping 1:1 to the pricing matrix. `hotels.plan_id` points to a plan. `Hotel` exposes `feature_enabled?`/`feature_level?`/`feature_addon?`. A `PlanGated` controller concern + view helper enforce access. An admin matrix UI toggles `plan_features`. Entitlements kept separate from the existing RBAC `permissions` system.

**Tech Stack:** Rails 8, PostgreSQL, RSpec + FactoryBot + shoulda-matchers, Hotwire (Turbo/Stimulus), Tailwind. "Pro" plan renamed **Plus**.

**Spec:** `docs/superpowers/specs/2026-06-08-plan-based-access-design.md`

**Codebase notes (verified):**
- Admin namespace is `admin/` (routes: `namespace :admin`, `app/controllers/admin/base_controller.rb`). Use `Admin::PlansController`.
- Hotel portal scoped `scope "/hotel/:hotel_id", module: :hotel_portal, as: :hotel`. `current_hotel` resolves in `ApplicationController`.
- `User#has_permission?` short-circuits `true` for `superadmin?`. Mirror this in plan gating.
- Hotel factory: `spec/factories/hotels.rb` (`status { "registered" }`).

---

## File Structure

- `db/migrate/*_create_plans.rb` — plans table
- `db/migrate/*_create_feature_groups.rb` — feature_groups table
- `db/migrate/*_create_features.rb` — features table
- `db/migrate/*_create_plan_features.rb` — plan_features join
- `db/migrate/*_add_plan_to_hotels.rb` — hotels.plan_id
- `app/models/plan.rb`, `feature_group.rb`, `feature.rb`, `plan_feature.rb` — models
- `app/models/hotel.rb` — add gating API (modify)
- `app/controllers/concerns/plan_gated.rb` — `require_feature!`
- `app/helpers/plan_features_helper.rb` — view helper
- `db/seeds/plans.rb` — matrix seed (idempotent)
- `app/controllers/admin/plans_controller.rb` — matrix UI
- `app/views/admin/plans/*` — matrix grid views
- `spec/factories/{plans,feature_groups,features,plan_features}.rb` — factories
- `spec/models/`, `spec/requests/` — specs

---

## Task 1: Create `plans` table + model

**Files:**
- Create: `db/migrate/TIMESTAMP_create_plans.rb`
- Create: `app/models/plan.rb`
- Create: `spec/factories/plans.rb`
- Create: `spec/models/plan_spec.rb`

- [ ] **Step 1: Generate migration**

Run: `bin/rails g migration CreatePlans`

Replace body with:
```ruby
class CreatePlans < ActiveRecord::Migration[8.0]
  def change
    create_table :plans do |t|
      t.string :name, null: false
      t.string :slug, null: false
      t.integer :position, null: false, default: 0
      t.boolean :most_popular, null: false, default: false
      t.boolean :active, null: false, default: true
      t.timestamps
    end
    add_index :plans, :slug, unique: true
  end
end
```

- [ ] **Step 2: Migrate**

Run: `bin/rails db:migrate`
Expected: `create_table(:plans)` success.

- [ ] **Step 3: Write model**

`app/models/plan.rb`:
```ruby
class Plan < ApplicationRecord
  has_many :plan_features, dependent: :destroy
  has_many :features, through: :plan_features
  has_many :hotels, dependent: :nullify

  validates :name, presence: true
  validates :slug, presence: true, uniqueness: true

  before_validation :generate_slug, on: :create

  scope :active, -> { where(active: true) }
  scope :ordered, -> { order(:position) }

  private

  def generate_slug
    self.slug ||= name&.parameterize if name.present?
  end
end
```

- [ ] **Step 4: Write factory**

`spec/factories/plans.rb`:
```ruby
FactoryBot.define do
  factory :plan do
    sequence(:name) { |n| "Plan #{n}" }
    sequence(:slug) { |n| "plan-#{n}" }
    position { 0 }
    most_popular { false }
    active { true }
  end
end
```

- [ ] **Step 5: Write model spec**

`spec/models/plan_spec.rb`:
```ruby
require "rails_helper"

RSpec.describe Plan, type: :model do
  it { is_expected.to have_many(:plan_features).dependent(:destroy) }
  it { is_expected.to have_many(:features).through(:plan_features) }
  it { is_expected.to validate_presence_of(:name) }

  it "generates slug from name on create" do
    plan = Plan.create!(name: "Plus Tier")
    expect(plan.slug).to eq("plus-tier")
  end

  it "enforces unique slug" do
    create(:plan, slug: "plus")
    dup = build(:plan, slug: "plus")
    expect(dup).not_to be_valid
  end
end
```

- [ ] **Step 6: Run spec**

Run: `bundle exec rspec spec/models/plan_spec.rb`
Expected: PASS (4 examples).

- [ ] **Step 7: Commit**

```bash
git add db/migrate db/schema.rb app/models/plan.rb spec/factories/plans.rb spec/models/plan_spec.rb
git commit -m "feat: add Plan model and table"
```

---

## Task 2: Create `feature_groups` table + model

**Files:**
- Create: `db/migrate/TIMESTAMP_create_feature_groups.rb`
- Create: `app/models/feature_group.rb`
- Create: `spec/factories/feature_groups.rb`
- Create: `spec/models/feature_group_spec.rb`

- [ ] **Step 1: Generate migration**

Run: `bin/rails g migration CreateFeatureGroups`

Body:
```ruby
class CreateFeatureGroups < ActiveRecord::Migration[8.0]
  def change
    create_table :feature_groups do |t|
      t.string :name, null: false
      t.string :slug, null: false
      t.integer :position, null: false, default: 0
      t.timestamps
    end
    add_index :feature_groups, :slug, unique: true
  end
end
```

- [ ] **Step 2: Migrate**

Run: `bin/rails db:migrate`

- [ ] **Step 3: Write model**

`app/models/feature_group.rb`:
```ruby
class FeatureGroup < ApplicationRecord
  has_many :features, -> { order(:position) }, dependent: :destroy

  validates :name, presence: true
  validates :slug, presence: true, uniqueness: true

  before_validation :generate_slug, on: :create

  scope :ordered, -> { order(:position) }

  private

  def generate_slug
    self.slug ||= name&.parameterize if name.present?
  end
end
```

- [ ] **Step 4: Write factory**

`spec/factories/feature_groups.rb`:
```ruby
FactoryBot.define do
  factory :feature_group do
    sequence(:name) { |n| "Group #{n}" }
    sequence(:slug) { |n| "group-#{n}" }
    position { 0 }
  end
end
```

- [ ] **Step 5: Write model spec**

`spec/models/feature_group_spec.rb`:
```ruby
require "rails_helper"

RSpec.describe FeatureGroup, type: :model do
  it { is_expected.to have_many(:features).dependent(:destroy) }
  it { is_expected.to validate_presence_of(:name) }

  it "generates slug from name" do
    expect(FeatureGroup.create!(name: "AI Concierge (AIC)").slug).to eq("ai-concierge-aic")
  end
end
```

- [ ] **Step 6: Run spec**

Run: `bundle exec rspec spec/models/feature_group_spec.rb`
Expected: PASS.

- [ ] **Step 7: Commit**

```bash
git add db/migrate db/schema.rb app/models/feature_group.rb spec/factories/feature_groups.rb spec/models/feature_group_spec.rb
git commit -m "feat: add FeatureGroup model and table"
```

---

## Task 3: Create `features` table + model

**Files:**
- Create: `db/migrate/TIMESTAMP_create_features.rb`
- Create: `app/models/feature.rb`
- Create: `spec/factories/features.rb`
- Create: `spec/models/feature_spec.rb`

- [ ] **Step 1: Generate migration**

Run: `bin/rails g migration CreateFeatures`

Body:
```ruby
class CreateFeatures < ActiveRecord::Migration[8.0]
  def change
    create_table :features do |t|
      t.references :feature_group, null: false, foreign_key: true
      t.string :name, null: false
      t.string :slug, null: false
      t.integer :position, null: false, default: 0
      t.boolean :leveled, null: false, default: false
      t.boolean :addon, null: false, default: false
      t.timestamps
    end
    add_index :features, :slug, unique: true
  end
end
```

- [ ] **Step 2: Migrate**

Run: `bin/rails db:migrate`

- [ ] **Step 3: Write model**

`app/models/feature.rb`:
```ruby
class Feature < ApplicationRecord
  belongs_to :feature_group
  has_many :plan_features, dependent: :destroy
  has_many :plans, through: :plan_features

  validates :name, presence: true
  validates :slug, presence: true, uniqueness: true

  before_validation :generate_slug, on: :create

  scope :ordered, -> { order(:position) }

  private

  def generate_slug
    self.slug ||= name&.parameterize.to_s.underscore if name.present?
  end
end
```

Note: slugs use underscores (`housekeeping_flow`) to match the code-check keys in the spec. `parameterize` yields hyphens, so `.underscore` converts. Seed (Task 8) sets slugs explicitly regardless.

- [ ] **Step 4: Write factory**

`spec/factories/features.rb`:
```ruby
FactoryBot.define do
  factory :feature do
    association :feature_group
    sequence(:name) { |n| "Feature #{n}" }
    sequence(:slug) { |n| "feature_#{n}" }
    position { 0 }
    leveled { false }
    addon { false }
  end
end
```

- [ ] **Step 5: Write model spec**

`spec/models/feature_spec.rb`:
```ruby
require "rails_helper"

RSpec.describe Feature, type: :model do
  it { is_expected.to belong_to(:feature_group) }
  it { is_expected.to have_many(:plan_features).dependent(:destroy) }
  it { is_expected.to validate_presence_of(:name) }

  it "enforces unique slug" do
    create(:feature, slug: "housekeeping_flow")
    expect(build(:feature, slug: "housekeeping_flow")).not_to be_valid
  end
end
```

- [ ] **Step 6: Run spec**

Run: `bundle exec rspec spec/models/feature_spec.rb`
Expected: PASS.

- [ ] **Step 7: Commit**

```bash
git add db/migrate db/schema.rb app/models/feature.rb spec/factories/features.rb spec/models/feature_spec.rb
git commit -m "feat: add Feature model and table"
```

---

## Task 4: Create `plan_features` join table + model

**Files:**
- Create: `db/migrate/TIMESTAMP_create_plan_features.rb`
- Create: `app/models/plan_feature.rb`
- Create: `spec/factories/plan_features.rb`
- Create: `spec/models/plan_feature_spec.rb`

- [ ] **Step 1: Generate migration**

Run: `bin/rails g migration CreatePlanFeatures`

Body:
```ruby
class CreatePlanFeatures < ActiveRecord::Migration[8.0]
  def change
    create_table :plan_features do |t|
      t.references :plan, null: false, foreign_key: true
      t.references :feature, null: false, foreign_key: true
      t.boolean :enabled, null: false, default: false
      t.string :level
      t.boolean :addon, null: false, default: false
      t.timestamps
    end
    add_index :plan_features, [ :plan_id, :feature_id ], unique: true
  end
end
```

- [ ] **Step 2: Migrate**

Run: `bin/rails db:migrate`

- [ ] **Step 3: Write model**

`app/models/plan_feature.rb`:
```ruby
class PlanFeature < ApplicationRecord
  belongs_to :plan
  belongs_to :feature

  LEVELS = %w[manual basic advanced full room_allotment].freeze

  validates :feature_id, uniqueness: { scope: :plan_id }
  validates :level, inclusion: { in: LEVELS }, allow_nil: true
end
```

- [ ] **Step 4: Write factory**

`spec/factories/plan_features.rb`:
```ruby
FactoryBot.define do
  factory :plan_feature do
    association :plan
    association :feature
    enabled { true }
    level { nil }
    addon { false }
  end
end
```

- [ ] **Step 5: Write model spec**

`spec/models/plan_feature_spec.rb`:
```ruby
require "rails_helper"

RSpec.describe PlanFeature, type: :model do
  it { is_expected.to belong_to(:plan) }
  it { is_expected.to belong_to(:feature) }

  it "rejects duplicate feature per plan" do
    plan = create(:plan)
    feature = create(:feature)
    create(:plan_feature, plan: plan, feature: feature)
    dup = build(:plan_feature, plan: plan, feature: feature)
    expect(dup).not_to be_valid
  end

  it "rejects invalid level" do
    expect(build(:plan_feature, level: "bogus")).not_to be_valid
  end

  it "allows nil level" do
    expect(build(:plan_feature, level: nil)).to be_valid
  end
end
```

- [ ] **Step 6: Run spec**

Run: `bundle exec rspec spec/models/plan_feature_spec.rb`
Expected: PASS.

- [ ] **Step 7: Commit**

```bash
git add db/migrate db/schema.rb app/models/plan_feature.rb spec/factories/plan_features.rb spec/models/plan_feature_spec.rb
git commit -m "feat: add PlanFeature join model and table"
```

---

## Task 5: Add `plan_id` to hotels

**Files:**
- Create: `db/migrate/TIMESTAMP_add_plan_to_hotels.rb`
- Modify: `app/models/hotel.rb` (add association)

- [ ] **Step 1: Generate migration**

Run: `bin/rails g migration AddPlanToHotels`

Body:
```ruby
class AddPlanToHotels < ActiveRecord::Migration[8.0]
  def change
    add_reference :hotels, :plan, null: true, foreign_key: true
  end
end
```

- [ ] **Step 2: Migrate**

Run: `bin/rails db:migrate`

- [ ] **Step 3: Add association to Hotel**

In `app/models/hotel.rb`, add near the other `belongs_to` lines (e.g. after `belongs_to :salesperson, ...`):
```ruby
  belongs_to :plan, optional: true
```

- [ ] **Step 4: Verify in console**

Run: `bin/rails runner "puts Hotel.new.respond_to?(:plan)"`
Expected: `true`

- [ ] **Step 5: Commit**

```bash
git add db/migrate db/schema.rb app/models/hotel.rb
git commit -m "feat: add plan reference to hotels"
```

---

## Task 6: Hotel gating API (`feature_enabled?` / `feature_level` / `feature_addon?`)

**Files:**
- Modify: `app/models/hotel.rb`
- Create: `spec/models/hotel_plan_gating_spec.rb`

- [ ] **Step 1: Write failing spec**

`spec/models/hotel_plan_gating_spec.rb`:
```ruby
require "rails_helper"

RSpec.describe Hotel, "plan gating", type: :model do
  let(:group) { create(:feature_group) }
  let(:plan)  { create(:plan) }
  let(:hotel) { create(:hotel, plan: plan) }

  def feature(slug, **opts)
    create(:feature, feature_group: group, slug: slug, **opts)
  end

  describe "#feature_enabled?" do
    it "true when plan_feature enabled" do
      f = feature("housekeeping_flow")
      create(:plan_feature, plan: plan, feature: f, enabled: true)
      expect(hotel.feature_enabled?("housekeeping_flow")).to be true
    end

    it "false when plan_feature disabled" do
      f = feature("housekeeping_flow")
      create(:plan_feature, plan: plan, feature: f, enabled: false)
      expect(hotel.feature_enabled?("housekeeping_flow")).to be false
    end

    it "false when no plan_feature row" do
      feature("housekeeping_flow")
      expect(hotel.feature_enabled?("housekeeping_flow")).to be false
    end

    it "false for unknown slug" do
      expect(hotel.feature_enabled?("nonexistent")).to be false
    end

    it "false when hotel has no plan" do
      f = feature("housekeeping_flow")
      create(:plan_feature, plan: plan, feature: f, enabled: true)
      no_plan = create(:hotel, plan: nil)
      expect(no_plan.feature_enabled?("housekeeping_flow")).to be false
    end
  end

  describe "#feature_level" do
    it "returns level when enabled" do
      f = feature("front_desk", leveled: true)
      create(:plan_feature, plan: plan, feature: f, enabled: true, level: "advanced")
      expect(hotel.feature_level("front_desk")).to eq("advanced")
    end

    it "returns nil when disabled even if level set" do
      f = feature("front_desk", leveled: true)
      create(:plan_feature, plan: plan, feature: f, enabled: false, level: "advanced")
      expect(hotel.feature_level("front_desk")).to be_nil
    end

    it "returns nil for nil-plan hotel" do
      expect(create(:hotel, plan: nil).feature_level("front_desk")).to be_nil
    end
  end

  describe "#feature_addon?" do
    it "true when addon cell set" do
      f = feature("e_invoice", addon: true)
      create(:plan_feature, plan: plan, feature: f, enabled: false, addon: true)
      expect(hotel.feature_addon?("e_invoice")).to be true
    end

    it "false for unknown slug" do
      expect(hotel.feature_addon?("nope")).to be false
    end
  end

  describe "memoization" do
    it "loads plan features once per instance" do
      f = feature("housekeeping_flow")
      create(:plan_feature, plan: plan, feature: f, enabled: true)
      hotel.feature_enabled?("housekeeping_flow")
      expect(hotel).not_to receive(:plan)  # map already memoized
      hotel.feature_enabled?("housekeeping_flow")
    end
  end
end
```

- [ ] **Step 2: Run spec, verify it fails**

Run: `bundle exec rspec spec/models/hotel_plan_gating_spec.rb`
Expected: FAIL — `NoMethodError: undefined method 'feature_enabled?'`.

- [ ] **Step 3: Implement gating API in Hotel**

In `app/models/hotel.rb`, add public methods (after the `belongs_to :plan` line region, in the instance-method body):
```ruby
  def plan_feature_map
    @plan_feature_map ||= begin
      if plan
        plan.plan_features
            .joins(:feature)
            .pluck("features.slug", :enabled, :level, :addon)
            .each_with_object({}) { |(slug, enabled, level, addon), h|
              h[slug] = { enabled: enabled, level: level, addon: addon }
            }
      else
        {}
      end
    end
  end

  def feature_enabled?(slug)
    !!plan_feature_map.dig(slug.to_s, :enabled)
  end

  def feature_level(slug)
    row = plan_feature_map[slug.to_s]
    return nil unless row && row[:enabled]
    row[:level]
  end

  def feature_addon?(slug)
    !!plan_feature_map.dig(slug.to_s, :addon)
  end
```

- [ ] **Step 4: Run spec, verify pass**

Run: `bundle exec rspec spec/models/hotel_plan_gating_spec.rb`
Expected: PASS (all examples).

- [ ] **Step 5: Commit**

```bash
git add app/models/hotel.rb spec/models/hotel_plan_gating_spec.rb
git commit -m "feat: add plan-based feature gating API to Hotel"
```

---

## Task 7: `PlanGated` controller concern

**Files:**
- Create: `app/controllers/concerns/plan_gated.rb`
- Create: `spec/requests/plan_gated_spec.rb`
- Modify: `app/controllers/application_controller.rb` (include concern)

- [ ] **Step 1: Write the concern**

`app/controllers/concerns/plan_gated.rb`:
```ruby
# frozen_string_literal: true

module PlanGated
  extend ActiveSupport::Concern

  private

  def require_feature!(slug)
    return true if current_user&.superadmin?
    return true if current_hotel&.feature_enabled?(slug)

    redirect_to(request.referrer || root_path,
                alert: "This feature isn't included in your plan. Upgrade to access it.")
    false
  end
end
```

- [ ] **Step 2: Include it in ApplicationController**

In `app/controllers/application_controller.rb`, after `include Pundit::Authorization`:
```ruby
  include PlanGated
```

- [ ] **Step 3: Write request spec with a throwaway controller**

`spec/requests/plan_gated_spec.rb`:
```ruby
require "rails_helper"

RSpec.describe "PlanGated concern", type: :request do
  before do
    Rails.application.routes.draw do
      get "/_test_gated", to: "test_gated#show"
    end

    stub_const("TestGatedController", Class.new(ApplicationController) do
      before_action -> { require_feature!("housekeeping_flow") }
      def show = render(plain: "ok")
      # bypass real auth for the test
      def current_user = @test_user
      def current_hotel = @test_hotel
    end)
  end

  after { Rails.application.reload_routes! }

  let(:group) { create(:feature_group) }
  let(:feature) { create(:feature, feature_group: group, slug: "housekeeping_flow") }

  it "allows when feature enabled" do
    plan = create(:plan)
    create(:plan_feature, plan: plan, feature: feature, enabled: true)
    hotel = create(:hotel, plan: plan)
    TestGatedController.any_instance.stub(:current_hotel).and_return(hotel)
    TestGatedController.any_instance.stub(:current_user).and_return(nil)

    get "/_test_gated"
    expect(response.body).to eq("ok")
  end

  it "blocks (redirect) when feature disabled" do
    hotel = create(:hotel, plan: create(:plan))
    TestGatedController.any_instance.stub(:current_hotel).and_return(hotel)
    TestGatedController.any_instance.stub(:current_user).and_return(nil)

    get "/_test_gated"
    expect(response).to have_http_status(:redirect)
  end
end
```

Note: if `any_instance.stub` style is unavailable, use `allow_any_instance_of(TestGatedController).to receive(:current_hotel).and_return(hotel)`. Confirm which RSpec mock syntax the repo uses by grepping `spec/` for `allow_any_instance_of`.

- [ ] **Step 4: Run spec**

Run: `bundle exec rspec spec/requests/plan_gated_spec.rb`
Expected: PASS (both examples).

- [ ] **Step 5: Commit**

```bash
git add app/controllers/concerns/plan_gated.rb app/controllers/application_controller.rb spec/requests/plan_gated_spec.rb
git commit -m "feat: add PlanGated controller concern"
```

---

## Task 8: View helper

**Files:**
- Create: `app/helpers/plan_features_helper.rb`
- Create: `spec/helpers/plan_features_helper_spec.rb`

- [ ] **Step 1: Write helper**

`app/helpers/plan_features_helper.rb`:
```ruby
module PlanFeaturesHelper
  # Hide/show UI by plan feature. Controller require_feature! is the real boundary.
  def feature_enabled_for_hotel?(slug, hotel = current_hotel)
    return true if current_user&.superadmin?
    hotel&.feature_enabled?(slug) || false
  end
end
```

- [ ] **Step 2: Write helper spec**

`spec/helpers/plan_features_helper_spec.rb`:
```ruby
require "rails_helper"

RSpec.describe PlanFeaturesHelper, type: :helper do
  let(:group) { create(:feature_group) }
  let(:plan)  { create(:plan) }
  let(:hotel) { create(:hotel, plan: plan) }

  before { allow(helper).to receive(:current_user).and_return(nil) }

  it "true when hotel feature enabled" do
    f = create(:feature, feature_group: group, slug: "ai_concierge_page")
    create(:plan_feature, plan: plan, feature: f, enabled: true)
    expect(helper.feature_enabled_for_hotel?("ai_concierge_page", hotel)).to be true
  end

  it "false when disabled" do
    expect(helper.feature_enabled_for_hotel?("ai_concierge_page", hotel)).to be false
  end
end
```

- [ ] **Step 3: Run spec**

Run: `bundle exec rspec spec/helpers/plan_features_helper_spec.rb`
Expected: PASS.

- [ ] **Step 4: Commit**

```bash
git add app/helpers/plan_features_helper.rb spec/helpers/plan_features_helper_spec.rb
git commit -m "feat: add plan feature view helper"
```

---

## Task 9: Seed the pricing matrix

Idempotent seed reflecting `WAStays_Pricing.png`. "Pro" → "Plus".

**Files:**
- Create: `db/seeds/plans.rb`
- Modify: `db/seeds.rb` (require the new file)

**Plan columns (position order):** easy(1), direct(2), core(3), plus(4, most_popular), enterprise(5).

**Cell encoding used below:** in each feature row, a hash maps plan-slug → cell.
Cell value: `true` = enabled ✓; `false`/absent = off; a string = enabled with that
level (`"manual"`, `"basic"`, `"advanced"`, `"full"`, `"room_allotment"`);
`:addon` = addon "+" (enabled:false, addon:true).

- [ ] **Step 1: Write seed file**

`db/seeds/plans.rb`:
```ruby
# Idempotent. Mirrors WAStays_Pricing.png. "Pro" column => "Plus".
PLAN_DEFS = [
  { slug: "easy",       name: "Easy",       position: 1, most_popular: false },
  { slug: "direct",     name: "Direct",     position: 2, most_popular: false },
  { slug: "core",       name: "Core",       position: 3, most_popular: false },
  { slug: "plus",       name: "Plus",       position: 4, most_popular: true  },
  { slug: "enterprise", name: "Enterprise", position: 5, most_popular: false },
].freeze

# group slug => [name, position]
GROUP_DEFS = {
  "aic"      => [ "AI Concierge (AIC)", 1 ],
  "be"       => [ "Booking Engine (BE)", 2 ],
  "cm"       => [ "Channel Manager (CM)", 3 ],
  "pms"      => [ "Property Management System (PMS)", 4 ],
  "rate"     => [ "Rate Management", 5 ],
  "hk"       => [ "Housekeeping", 6 ],
  "guest"    => [ "Guest Database & Profile", 7 ],
  "report"   => [ "Reporting", 8 ],
  "comms"    => [ "Communication & Notifications", 9 ],
  "system"   => [ "System & Access Control", 10 ],
  "addons"   => [ "Add-ons", 11 ],
}.freeze

# Each feature: [group, slug, name, leveled, addon, { plan_slug => cell }]
# cell: true / level-string / :addon ; missing => off
FEATURE_DEFS = [
  # --- AIC ---
  [ "aic", "whatsapp_automation_flows", "WhatsApp automation flows", false, false,
    { "easy"=>true,"direct"=>true,"core"=>true,"plus"=>true,"enterprise"=>true } ],
  [ "aic", "llm_hotels_resorts_homestays", "LLM — hotels, resorts & homestays", false, false,
    { "easy"=>true,"direct"=>true,"core"=>true,"plus"=>true,"enterprise"=>true } ],
  [ "aic", "guest_engagement_flow", "Guest engagement flow", false, false,
    { "easy"=>true,"direct"=>true,"core"=>true,"plus"=>true,"enterprise"=>true } ],
  [ "aic", "ai_concierge_flow", "AI concierge flow", false, false,
    { "easy"=>true,"direct"=>true,"core"=>true,"plus"=>true,"enterprise"=>true } ],
  [ "aic", "activity_offers_flow", "Activity & offers flow", false, false,
    { "easy"=>true,"direct"=>true,"core"=>true,"plus"=>true,"enterprise"=>true } ],
  [ "aic", "housekeeping_flow", "Housekeeping flow", false, false,
    { "core"=>true,"plus"=>true,"enterprise"=>true } ],
  [ "aic", "complaint_system_flow", "Complaint system flow", false, false,
    { "core"=>true,"plus"=>true,"enterprise"=>true } ],
  [ "aic", "ai_concierge_page", "AI Concierge Page", false, false,
    { "core"=>true,"plus"=>true,"enterprise"=>true } ],
  # --- BE ---
  [ "be", "payment_system", "Payment system", false, false,
    { "direct"=>true,"core"=>true,"plus"=>true,"enterprise"=>true } ],
  [ "be", "billing_invoicing_system", "Billing & invoicing system", false, false,
    { "direct"=>true,"core"=>true,"plus"=>true,"enterprise"=>true } ],
  [ "be", "direct_booking_flow", "Direct booking flow", false, false,
    { "direct"=>true,"core"=>true,"plus"=>true,"enterprise"=>true } ],
  [ "be", "folio_management_billing", "Folio Management & Billing", false, false,
    { "direct"=>true,"core"=>true,"plus"=>true,"enterprise"=>true } ],
  # --- CM ---
  [ "cm", "manage_40_otas", "Manage 40+ OTAs at one go", false, false,
    { "plus"=>true,"enterprise"=>true } ],
  [ "cm", "auto_sync_availability", "Auto-sync availability across OTAs & direct", false, false,
    { "plus"=>true,"enterprise"=>true } ],
  # --- PMS ---
  [ "pms", "reservation_management", "Reservation Management", true, false,
    { "direct"=>"manual","core"=>true,"plus"=>true,"enterprise"=>true } ],
  [ "pms", "room_management_availability", "Room Management & Availability", true, false,
    { "direct"=>"manual","core"=>"room_allotment","plus"=>true,"enterprise"=>true } ],
  [ "pms", "front_desk_operations", "Front Desk Operations", true, false,
    { "direct"=>"manual","core"=>"basic","plus"=>"basic","enterprise"=>"advanced" } ],
  # --- Rate Management ---
  [ "rate", "rate_plan_hierarchy", "Rate plan hierarchy", true, false,
    { "direct"=>"manual","core"=>"basic","plus"=>"basic","enterprise"=>"full" } ],
  [ "rate", "date_range_dow_pricing", "Date-range & day-of-week pricing", true, false,
    { "direct"=>"manual","core"=>true,"plus"=>true,"enterprise"=>true } ],
  [ "rate", "rate_override_reason_code", "Rate override with reason code", false, false,
    { "enterprise"=>true } ],
  [ "rate", "min_max_stay_rules", "Min/max stay rules", false, false,
    { "enterprise"=>true } ],
  [ "rate", "last_minute_rate_automation", "Last-minute rate automation", false, false,
    { "enterprise"=>true } ],
  [ "rate", "instant_rate_sync", "Instant rate sync", false, false,
    { "enterprise"=>true } ],
  # --- Housekeeping ---
  [ "hk", "task_assignment_minibar_log", "Task assignment & minibar log", false, false,
    { "core"=>true,"plus"=>true,"enterprise"=>true } ],
  [ "hk", "maintenance_request_tracking", "Maintenance request tracking", false, false,
    { "core"=>true,"plus"=>true,"enterprise"=>true } ],
  [ "hk", "room_status_board", "Room status board", false, false,
    { "enterprise"=>true } ],
  [ "hk", "priority_room_flagging", "Priority room flagging", false, false,
    { "enterprise"=>true } ],
  # --- Guest DB ---
  [ "guest", "unified_guest_profile", "Unified guest profile", false, false,
    { "easy"=>true,"direct"=>true,"core"=>true,"plus"=>true,"enterprise"=>true } ],
  [ "guest", "preference_tagging", "Preference tagging", false, false,
    { "enterprise"=>true } ],
  [ "guest", "complaint_history", "Complaint history", false, false,
    { "enterprise"=>true } ],
  [ "guest", "vip_blacklist_flag", "VIP & Blacklist flag", false, false,
    { "enterprise"=>true } ],
  [ "guest", "whatsapp_linked_to_profile", "WhatsApp number linked to profile", false, false,
    { "enterprise"=>true } ],
  # --- Reporting ---
  [ "report", "daily_occupancy_revenue", "Daily occupancy & revenue report", false, false,
    { "core"=>true,"plus"=>true,"enterprise"=>true } ],
  [ "report", "arrivals_departures_list", "Arrivals & departures list", false, false,
    { "core"=>true,"plus"=>true,"enterprise"=>true } ],
  [ "report", "outstanding_balance_noshow", "Outstanding balance / no-show / cancellation", false, false,
    { "core"=>true,"plus"=>true,"enterprise"=>true } ],
  [ "report", "excel_pdf_export", "Excel / PDF export", false, false,
    { "core"=>true,"plus"=>true,"enterprise"=>true } ],
  [ "report", "housekeeper_productivity", "Housekeeper productivity report", false, false,
    { "core"=>true,"plus"=>true,"enterprise"=>true } ],
  [ "report", "booking_source_analysis", "Booking source analysis", false, false,
    { "plus"=>true,"enterprise"=>true } ],
  [ "report", "revenue_allocation_per_night", "Revenue allocation (per night)", false, false,
    { "enterprise"=>true } ],
  [ "report", "backdated_checkin_rate", "Backdated check-in & rate report", false, false,
    { "enterprise"=>true } ],
  # --- Comms ---
  [ "comms", "welcoming_instay_messaging", "Welcoming & in-stay messaging", false, false,
    { "easy"=>true,"direct"=>true,"core"=>true,"plus"=>true,"enterprise"=>true } ],
  [ "comms", "checkout_receipt_review", "Check-out receipt & review request", false, false,
    { "easy"=>true,"direct"=>true,"core"=>true,"plus"=>true,"enterprise"=>true } ],
  [ "comms", "automated_prearrival", "Automated pre-arrival WhatsApp/email", false, false,
    { "core"=>true,"plus"=>true,"enterprise"=>true } ],
  [ "comms", "checkin_confirmation", "Check-in confirmation message", false, false,
    { "core"=>true,"plus"=>true,"enterprise"=>true } ],
  [ "comms", "internal_staff_alerts", "Internal staff alerts", false, false,
    { "core"=>true,"plus"=>true,"enterprise"=>true } ],
  # --- System & Access ---
  [ "system", "role_based_access_control", "Role-based access control", false, false,
    { "core"=>true,"plus"=>true,"enterprise"=>true } ],
  [ "system", "mobile_friendly_management", "Mobile-friendly management view", false, false,
    { "core"=>true,"plus"=>true,"enterprise"=>true } ],
  [ "system", "no_show_auto_handling", "No-show auto-handling", false, false,
    { "core"=>true,"plus"=>true,"enterprise"=>true } ],
  [ "system", "full_audit_trail", "Full audit trail", false, false,
    { "enterprise"=>true } ],
  [ "system", "offline_mode", "Offline mode / graceful degradation", false, false,
    { "enterprise"=>true } ],
  [ "system", "multi_property_view", "Multi-property view", false, false,
    { "enterprise"=>true } ],
  [ "system", "shift_handover_log", "Shift handover log", false, false,
    { "enterprise"=>true } ],
  # --- Add-ons (orange "+") ---
  [ "addons", "live_chat", "Live chat", false, true,
    { "easy"=>:addon,"direct"=>:addon,"core"=>:addon,"plus"=>:addon,"enterprise"=>:addon } ],
  [ "addons", "e_invoice", "E-invoice", false, true,
    { "core"=>:addon,"plus"=>:addon,"enterprise"=>:addon } ],
  [ "addons", "accounting_integration", "Accounting integration", false, true,
    { "core"=>:addon,"plus"=>:addon,"enterprise"=>:addon } ],
  [ "addons", "per_pax_booking", "Per pax booking", false, true,
    { "enterprise"=>:addon } ],
].freeze

ActiveRecord::Base.transaction do
  plans = PLAN_DEFS.to_h do |d|
    plan = Plan.find_or_initialize_by(slug: d[:slug])
    plan.update!(name: d[:name], position: d[:position], most_popular: d[:most_popular], active: true)
    [ d[:slug], plan ]
  end

  groups = GROUP_DEFS.to_h do |slug, (name, pos)|
    g = FeatureGroup.find_or_initialize_by(slug: slug)
    g.update!(name: name, position: pos)
    [ slug, g ]
  end

  FEATURE_DEFS.each_with_index do |(group_slug, slug, name, leveled, addon, cells), idx|
    feature = Feature.find_or_initialize_by(slug: slug)
    feature.update!(feature_group: groups.fetch(group_slug), name: name,
                    position: idx, leveled: leveled, addon: addon)

    cells.each do |plan_slug, cell|
      pf = PlanFeature.find_or_initialize_by(plan: plans.fetch(plan_slug), feature: feature)
      enabled = cell != :addon && !cell.nil? && cell != false
      level   = cell.is_a?(String) ? cell : nil
      is_addon = cell == :addon
      pf.update!(enabled: enabled, level: level, addon: is_addon)
    end
  end
end

puts "Seeded #{Plan.count} plans, #{Feature.count} features, #{PlanFeature.count} plan_features."
```

- [ ] **Step 2: Require from main seeds**

In `db/seeds.rb`, add:
```ruby
load Rails.root.join("db/seeds/plans.rb")
```
(If `db/seeds.rb` already loads other files conditionally, follow that pattern.)

- [ ] **Step 3: Run seed twice (idempotency check)**

Run: `bin/rails db:seed && bin/rails db:seed`
Expected: second run does not error or duplicate; final `PlanFeature.count` stable.

- [ ] **Step 4: Commit**

```bash
git add db/seeds/plans.rb db/seeds.rb
git commit -m "feat: seed subscription plan matrix"
```

---

## Task 10: Admin matrix UI (view + edit plan_features)

**Files:**
- Modify: `config/routes.rb` (add admin plans routes)
- Create: `app/controllers/admin/plans_controller.rb`
- Create: `app/views/admin/plans/index.html.erb`
- Create: `spec/requests/admin/plans_spec.rb`

**Pattern:** follow existing `app/controllers/admin/base_controller.rb` (superadmin auth). Verify its before_action by reading it first.

- [ ] **Step 1: Read existing admin base controller**

Run: `cat app/controllers/admin/base_controller.rb`
Confirm it authenticates superadmin. The new controller inherits from `Admin::BaseController`.

- [ ] **Step 2: Add routes**

In `config/routes.rb`, inside the existing `namespace :admin do ... end` block:
```ruby
    resources :plans, only: [ :index ] do
      collection do
        patch :update_matrix
      end
    end
```

- [ ] **Step 3: Write controller**

`app/controllers/admin/plans_controller.rb`:
```ruby
# frozen_string_literal: true

module Admin
  class PlansController < BaseController
    def index
      @plans = Plan.ordered
      @feature_groups = FeatureGroup.ordered.includes(:features)
      @plan_features = PlanFeature.all.index_by { |pf| [ pf.plan_id, pf.feature_id ] }
    end

    # Receives params[:cells] => [{ plan_id:, feature_id:, enabled:, level:, addon: }, ...]
    def update_matrix
      cells = params.fetch(:cells, []).values
      PlanFeature.transaction do
        cells.each do |c|
          pf = PlanFeature.find_or_initialize_by(plan_id: c[:plan_id], feature_id: c[:feature_id])
          pf.enabled = ActiveModel::Type::Boolean.new.cast(c[:enabled])
          pf.level   = c[:level].presence
          pf.addon   = ActiveModel::Type::Boolean.new.cast(c[:addon])
          pf.save!
        end
      end
      redirect_to admin_plans_path, notice: "Plan matrix updated."
    end
  end
end
```

- [ ] **Step 4: Write index view**

`app/views/admin/plans/index.html.erb`:
```erb
<div class="p-6">
  <h1 class="text-xl font-semibold mb-4">Subscription Plans</h1>

  <%= form_with url: update_matrix_admin_plans_path, method: :patch do |f| %>
    <table class="min-w-full text-sm border">
      <thead>
        <tr>
          <th class="text-left p-2">Feature</th>
          <% @plans.each do |plan| %>
            <th class="p-2 text-center">
              <%= plan.name %>
              <% if plan.most_popular %><span class="text-amber-500">★</span><% end %>
            </th>
          <% end %>
        </tr>
      </thead>
      <tbody>
        <% idx = 0 %>
        <% @feature_groups.each do |group| %>
          <tr class="bg-gray-100">
            <td class="p-2 font-semibold" colspan="<%= @plans.size + 1 %>"><%= group.name %></td>
          </tr>
          <% group.features.each do |feature| %>
            <tr class="border-t">
              <td class="p-2"><%= feature.name %></td>
              <% @plans.each do |plan| %>
                <% pf = @plan_features[[ plan.id, feature.id ]] %>
                <td class="p-2 text-center">
                  <input type="hidden" name="cells[<%= idx %>][plan_id]" value="<%= plan.id %>">
                  <input type="hidden" name="cells[<%= idx %>][feature_id]" value="<%= feature.id %>">
                  <input type="hidden" name="cells[<%= idx %>][enabled]" value="0">
                  <input type="checkbox" name="cells[<%= idx %>][enabled]" value="1"
                         <%= "checked" if pf&.enabled %>>
                  <% if feature.leveled %>
                    <%= select_tag "cells[#{idx}][level]",
                          options_for_select(PlanFeature::LEVELS, pf&.level),
                          include_blank: true, class: "text-xs border ml-1" %>
                  <% end %>
                  <% if feature.addon %>
                    <input type="hidden" name="cells[<%= idx %>][addon]" value="0">
                    <label class="text-xs text-amber-600">
                      <input type="checkbox" name="cells[<%= idx %>][addon]" value="1"
                             <%= "checked" if pf&.addon %>> +
                    </label>
                  <% end %>
                  <% idx += 1 %>
                </td>
              <% end %>
            </tr>
          <% end %>
        <% end %>
      </tbody>
    </table>
    <%= f.submit "Save matrix", class: "mt-4 px-4 py-2 bg-blue-600 text-white rounded" %>
  <% end %>
</div>
```

Note: plain form-post (no Stimulus required to be functional). A Stimulus controller for inline auto-save is optional polish, not required for this task.

- [ ] **Step 5: Write request spec**

`spec/requests/admin/plans_spec.rb`:
```ruby
require "rails_helper"

RSpec.describe "Admin::Plans", type: :request do
  let(:account) { create(:account) }
  let(:superadmin) { create(:user, account: account, role: "superadmin") }

  before do
    # Match the repo's login helper; inspect spec/support for session helpers.
    # Fallback: set session directly.
    post login_path, params: { email: superadmin.email, password: "password" } rescue nil
  end

  it "renders the matrix" do
    create(:plan, slug: "plus", position: 4)
    group = create(:feature_group)
    create(:feature, feature_group: group, slug: "housekeeping_flow")

    get admin_plans_path
    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Subscription Plans")
  end

  it "updates plan_features via update_matrix" do
    plan = create(:plan)
    group = create(:feature_group)
    feature = create(:feature, feature_group: group, slug: "housekeeping_flow")

    patch update_matrix_admin_plans_path, params: {
      cells: { "0" => { plan_id: plan.id, feature_id: feature.id, enabled: "1" } }
    }
    expect(PlanFeature.find_by(plan: plan, feature: feature).enabled).to be true
  end
end
```

Note: the login step depends on the repo's auth test helper. Before running, grep `spec/support` and existing `spec/requests/admin` specs for the established sign-in pattern and reuse it (e.g. a `sign_in(user)` helper or session stub). Do not invent a new auth flow.

- [ ] **Step 6: Run spec**

Run: `bundle exec rspec spec/requests/admin/plans_spec.rb`
Expected: PASS.

- [ ] **Step 7: Commit**

```bash
git add config/routes.rb app/controllers/admin/plans_controller.rb app/views/admin/plans spec/requests/admin/plans_spec.rb
git commit -m "feat: add admin plan matrix UI"
```

---

## Task 11: Hotel plan assignment (admin)

Let admin set a hotel's plan. Hook into the existing admin hotel edit form.

**Files:**
- Read first: `app/controllers/admin/hotels_controller.rb` + `app/views/admin/hotels/` (find the edit form + strong params)
- Modify: `app/controllers/admin/hotels_controller.rb` (permit `:plan_id`)
- Modify: the admin hotel form partial (add plan dropdown)
- Create: `spec/requests/admin/hotel_plan_assignment_spec.rb`

- [ ] **Step 1: Inspect existing admin hotels controller + form**

Run: `cat app/controllers/admin/hotels_controller.rb`
Run: `ls app/views/admin/hotels`
Identify the `hotel_params` permit list and the form partial (likely `_form.html.erb`).

- [ ] **Step 2: Permit plan_id**

In `hotel_params` (or equivalent) in `app/controllers/admin/hotels_controller.rb`, add `:plan_id` to the permitted attributes list. Show the exact edited line, e.g.:
```ruby
params.require(:hotel).permit(
  # ...existing attrs...,
  :plan_id
)
```

- [ ] **Step 3: Add dropdown to the form**

In the admin hotel form partial, add:
```erb
<div class="mb-4">
  <%= form.label :plan_id, "Subscription plan", class: "block text-sm font-medium" %>
  <%= form.collection_select :plan_id, Plan.active.ordered, :id, :name,
        { include_blank: "— No plan —" }, class: "border rounded p-2 w-full" %>
</div>
```

- [ ] **Step 4: Write request spec**

`spec/requests/admin/hotel_plan_assignment_spec.rb`:
```ruby
require "rails_helper"

RSpec.describe "Admin hotel plan assignment", type: :request do
  let(:account) { create(:account) }
  let(:superadmin) { create(:user, account: account, role: "superadmin") }

  before do
    # Reuse the repo's established admin sign-in helper (see other admin specs).
    post login_path, params: { email: superadmin.email, password: "password" } rescue nil
  end

  it "assigns a plan to a hotel" do
    hotel = create(:hotel, account: account)
    plan  = create(:plan, slug: "plus")

    patch admin_hotel_path(hotel), params: { hotel: { plan_id: plan.id } }
    expect(hotel.reload.plan).to eq(plan)
  end
end
```

Note: confirm the admin hotel update route name (`admin_hotel_path`) and the sign-in helper by reading existing admin hotel specs before running.

- [ ] **Step 5: Run spec**

Run: `bundle exec rspec spec/requests/admin/hotel_plan_assignment_spec.rb`
Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add app/controllers/admin/hotels_controller.rb app/views/admin/hotels spec/requests/admin/hotel_plan_assignment_spec.rb
git commit -m "feat: allow admin to assign plan to hotel"
```

---

## Task 12: Seed sanity spec + full suite

**Files:**
- Create: `spec/seeds/plans_seed_spec.rb` (or `spec/lib/`)

- [ ] **Step 1: Write seed spec**

`spec/seeds/plans_seed_spec.rb`:
```ruby
require "rails_helper"

RSpec.describe "plans seed", type: :model do
  before { load Rails.root.join("db/seeds/plans.rb") }

  it "creates the 5 plans with Plus renamed and flagged popular" do
    expect(Plan.pluck(:slug)).to match_array(%w[easy direct core plus enterprise])
    expect(Plan.find_by(slug: "plus").most_popular).to be true
    expect(Plan.where(name: "Pro")).to be_empty
  end

  it "enables AIC base flows on all plans" do
    feature = Feature.find_by(slug: "whatsapp_automation_flows")
    enabled_plan_slugs = PlanFeature.where(feature: feature, enabled: true)
                                    .joins(:plan).pluck("plans.slug")
    expect(enabled_plan_slugs).to match_array(%w[easy direct core plus enterprise])
  end

  it "restricts channel manager to plus + enterprise" do
    feature = Feature.find_by(slug: "manage_40_otas")
    slugs = PlanFeature.where(feature: feature, enabled: true).joins(:plan).pluck("plans.slug")
    expect(slugs).to match_array(%w[plus enterprise])
  end

  it "sets front desk levels: direct=manual, core/plus=basic, enterprise=advanced" do
    feature = Feature.find_by(slug: "front_desk_operations")
    levels = PlanFeature.where(feature: feature).joins(:plan)
                        .pluck("plans.slug", :level).to_h
    expect(levels["direct"]).to eq("manual")
    expect(levels["core"]).to eq("basic")
    expect(levels["plus"]).to eq("basic")
    expect(levels["enterprise"]).to eq("advanced")
  end

  it "marks add-ons as addon cells, not enabled" do
    feature = Feature.find_by(slug: "live_chat")
    pf = PlanFeature.find_by(feature: feature, plan: Plan.find_by(slug: "easy"))
    expect(pf.addon).to be true
    expect(pf.enabled).to be false
  end

  it "is idempotent" do
    before_count = PlanFeature.count
    load Rails.root.join("db/seeds/plans.rb")
    expect(PlanFeature.count).to eq(before_count)
  end
end
```

- [ ] **Step 2: Run seed spec**

Run: `bundle exec rspec spec/seeds/plans_seed_spec.rb`
Expected: PASS.

- [ ] **Step 3: Run full plan-related suite**

Run:
```bash
bundle exec rspec spec/models/plan_spec.rb spec/models/feature_group_spec.rb \
  spec/models/feature_spec.rb spec/models/plan_feature_spec.rb \
  spec/models/hotel_plan_gating_spec.rb spec/requests/plan_gated_spec.rb \
  spec/helpers/plan_features_helper_spec.rb spec/requests/admin/plans_spec.rb \
  spec/requests/admin/hotel_plan_assignment_spec.rb spec/seeds/plans_seed_spec.rb
```
Expected: all PASS.

- [ ] **Step 4: Run rubocop on new files**

Run: `bundle exec rubocop app/models/plan.rb app/models/feature_group.rb app/models/feature.rb app/models/plan_feature.rb app/controllers/concerns/plan_gated.rb app/controllers/admin/plans_controller.rb app/helpers/plan_features_helper.rb`
Expected: no offenses (fix any reported).

- [ ] **Step 5: Final commit**

```bash
git add spec/seeds/plans_seed_spec.rb
git commit -m "test: add plan matrix seed sanity specs"
```

---

## Done criteria
- Hotel with a plan gates features via `feature_enabled?` / `feature_level` / `feature_addon?`.
- Controllers block ungated access (`require_feature!`), superadmin bypasses.
- Admin can edit the plan matrix and assign plans to hotels.
- Seed reproduces the pricing image (Pro → Plus), idempotent.
- All specs + rubocop green.

## Wiring real features (follow-up, not in this plan)
This plan builds the gating mechanism + matrix. Actually attaching `require_feature!`
to existing real controllers (channel manager, housekeeping, reporting, etc.) and
wrapping nav links in `feature_enabled_for_hotel?` is a per-feature rollout done
incrementally afterward, once the mechanism is verified.
