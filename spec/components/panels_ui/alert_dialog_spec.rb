# frozen_string_literal: true

require "rails_helper"

RSpec.describe PanelsUI::AlertDialog, type: :component do
  def render_alert_dialog(**options)
    render_inline(described_class.new(**{
      id: "confirmation",
      title: "Continue?",
      description: "This change applies immediately."
    }.merge(options))) do |dialog|
      yield dialog if block_given?
    end
  end

  def render_complete(**options)
    render_alert_dialog(**options) do |dialog|
      dialog.with_cancel(label: "Cancel")
      dialog.with_action(label: "Continue")
      yield dialog if block_given?
    end
  end

  describe "structure and accessibility" do
    before { render_complete }

    it "renders a named and described native alert dialog" do
      expect(page).to have_css(
        "dialog#confirmation[role='alertdialog'][aria-modal='true']" \
        "[aria-labelledby='confirmation-title'][aria-describedby='confirmation-description']"
      )
      expect(page).to have_css("h2#confirmation-title[data-slot='alert-dialog-title']", text: "Continue?")
      expect(page).to have_css(
        "p#confirmation-description[data-slot='alert-dialog-description']",
        text: "This change applies immediately."
      )
    end

    it "reuses the non-dismissible native dialog lifecycle" do
      expect(page).to have_css(
        "dialog[data-controller~='panels-ui--dialog']" \
        "[data-panels-ui--dialog-dismissible-value='false']"
      )
      expect(page).to have_no_css("button[aria-label='Close']")
    end

    it "renders explicit responses and initially focuses cancel" do
      expect(page).to have_css("[data-slot='alert-dialog-cancel'][autofocus]", text: "Cancel")
      expect(page).to have_css("[data-slot='alert-dialog-action']", text: "Continue")
      expect(page).to have_css("[data-slot='alert-dialog-footer']")
    end
  end

  describe "required content" do
    it "requires a title" do
      expect { render_complete(title: nil) }.to raise_error(ArgumentError, "AlertDialog requires a title")
    end

    it "requires a description" do
      expect { render_complete(description: nil) }.to raise_error(ArgumentError, "AlertDialog requires a description")
    end

    it "requires cancel and action responses" do
      expect {
        render_alert_dialog { |dialog| dialog.with_action(label: "Continue") }
      }.to raise_error(ArgumentError, "AlertDialog requires a cancel response")

      expect {
        render_alert_dialog { |dialog| dialog.with_cancel(label: "Cancel") }
      }.to raise_error(ArgumentError, "AlertDialog requires an action response")
    end
  end

  describe "sizes and tones" do
    it "supports default and small sizes and falls back for unknown values" do
      render_complete(size: :sm)
      expect(page).to have_css("dialog[data-size='sm']")

      render_complete(size: :huge)
      expect(page).to have_css("dialog[data-size='default']")
    end

    {
      default: "primary",
      info: "info",
      warning: "warning",
      success: "success",
      destructive: "destructive"
    }.each do |tone, action_variant|
      it "maps #{tone} tone to the #{action_variant} action" do
        render_complete(tone: tone)

        expect(page).to have_css("dialog[data-tone='#{tone}']")
        expect(page).to have_css("[data-slot='alert-dialog-action'][data-variant='#{action_variant}']")
        cancel_variant = tone == :default ? "neutral" : "ghost"
        expect(page).to have_css("[data-slot='alert-dialog-cancel'][data-variant='#{cancel_variant}']")
      end
    end

    it "falls back to the default tone and permits response overrides" do
      render_alert_dialog(tone: :unknown) do |dialog|
        dialog.with_cancel(label: "Back", variant: :secondary)
        dialog.with_action(label: "Review", variant: :accent)
      end

      expect(page).to have_css("dialog[data-tone='default']")
      expect(page).to have_css("[data-slot='alert-dialog-cancel'][data-variant='secondary']")
      expect(page).to have_css("[data-slot='alert-dialog-action'][data-variant='accent']")
    end
  end

  describe "composition" do
    it "renders an optional icon with tone styling hooks" do
      render_complete(tone: :warning) do |dialog|
        dialog.with_icon { '<svg data-test-icon="warning"></svg>'.html_safe }
      end

      expect(page).to have_css("[data-slot='alert-dialog-icon'] svg[data-test-icon='warning']")
    end

    it "omits the icon wrapper when no icon is supplied" do
      render_complete
      expect(page).to have_no_css("[data-slot='alert-dialog-icon']")
    end

    it "renders link and non-GET method actions" do
      render_alert_dialog do |dialog|
        dialog.with_cancel(label: "Cancel")
        dialog.with_action(label: "Review", href: "/rooms")
      end
      expect(page).to have_link("Review", href: "/rooms")

      render_alert_dialog do |dialog|
        dialog.with_cancel(label: "Cancel")
        dialog.with_action(label: "Delete", href: "/rooms/1", method: :delete)
      end
      expect(page).to have_css("form.contents[action='/rooms/1'][method='post']")
      expect(page).to have_button("Delete")
      expect(page).to have_css("input[name='_method'][value='delete']", visible: :hidden)
    end

    it "merges caller controllers, actions, attributes, and class overrides" do
      render_alert_dialog(
        class: "rounded-2xl",
        data: { controller: "example", action: "example:event->example#handle" },
        aria: { live: "assertive" }
      ) do |dialog|
        dialog.with_cancel(label: "Cancel", data: { action: "example#cancel" })
        dialog.with_action(label: "Continue", data: { action: "example#continue" })
      end

      root = page.find("dialog")
      expect(root[:class]).to include("rounded-2xl")
      expect(root["data-controller"]).to eq("panels-ui--dialog example")
      expect(root["data-action"]).to include("example:event->example#handle")
      expect(root["aria-live"]).to eq("assertive")
      expect(page.find("[data-slot='alert-dialog-cancel']")["data-action"]).to eq(
        "example#cancel panels-ui--dialog#close"
      )
      expect(page.find("[data-slot='alert-dialog-action']")["data-action"]).to eq(
        "example#continue panels-ui--dialog#close"
      )
    end
  end
end
