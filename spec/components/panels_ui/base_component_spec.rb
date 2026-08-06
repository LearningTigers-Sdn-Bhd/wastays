# frozen_string_literal: true

require "rails_helper"

RSpec.describe PanelsUI::BaseComponent, type: :component do
  let(:component_class) do
    Class.new(described_class) do
      style base: "inline-flex p-2",
            variants: {
              variant: { solid: "bg-primary", ghost: "bg-transparent" },
              size: { sm: "h-8", md: "h-10" }
            },
            defaults: { variant: :solid, size: :md }
    end
  end

  it "resolves defaults and valid selections" do
    component = component_class.new

    expect(component.class_for).to include("inline-flex", "bg-primary", "h-10")
    expect(component.class_for(variant: :ghost, size: :sm)).to include("bg-transparent", "h-8")
  end

  it "falls back to each group default for nil and unknown selections" do
    component = component_class.new

    expect(component.class_for(variant: nil, size: :huge)).to include("bg-primary", "h-10")
    expect(component.class_for(variant: :unknown)).not_to include("bg-transparent")
  end

  it "inherits style configuration and merges caller overrides last" do
    subclass = Class.new(component_class)
    classes = subclass.new.class_for(class_override: "block p-6")

    expect(classes).to include("block", "p-6", "bg-primary", "h-10")
    expect(classes).not_to include("inline-flex", "p-2")
  end

  it "ignores selections for undeclared variant groups" do
    expect(component_class.new.class_for(tone: :quiet)).to include("bg-primary", "h-10")
  end
end
