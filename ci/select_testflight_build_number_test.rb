#!/usr/bin/env ruby
# frozen_string_literal: true

require "minitest/autorun"
require "tempfile"
require_relative "select_testflight_build_number"

class TestFlightBuildNumberSelectorTest < Minitest::Test
  def test_selects_one_when_app_store_connect_has_no_builds_for_version
    assert_equal(
      "1",
      TestFlightBuildNumberSelector.select_build_number(
        requested_build_number: "",
        latest_build_number: nil
      )
    )
  end

  def test_selects_next_integer_build_number
    assert_equal(
      "19",
      TestFlightBuildNumberSelector.select_build_number(
        requested_build_number: "",
        latest_build_number: "18"
      )
    )
  end

  def test_selects_next_dotted_build_number
    assert_equal(
      "1.4",
      TestFlightBuildNumberSelector.select_build_number(
        requested_build_number: "",
        latest_build_number: "1.3"
      )
    )
  end

  def test_accepts_requested_build_number_above_latest
    assert_equal(
      "20",
      TestFlightBuildNumberSelector.select_build_number(
        requested_build_number: "20",
        latest_build_number: "19"
      )
    )
  end

  def test_rejects_requested_build_number_equal_to_latest
    error = assert_raises(TestFlightBuildNumberSelector::SelectionError) do
      TestFlightBuildNumberSelector.select_build_number(
        requested_build_number: "19",
        latest_build_number: "19"
      )
    end

    assert_includes(error.message, "must be greater")
  end

  def test_rejects_requested_build_number_below_latest
    error = assert_raises(TestFlightBuildNumberSelector::SelectionError) do
      TestFlightBuildNumberSelector.select_build_number(
        requested_build_number: "18",
        latest_build_number: "19"
      )
    end

    assert_includes(error.message, "must be greater")
  end

  def test_rejects_malformed_requested_build_number
    error = assert_raises(TestFlightBuildNumberSelector::SelectionError) do
      TestFlightBuildNumberSelector.select_build_number(
        requested_build_number: "build-20",
        latest_build_number: "19"
      )
    end

    assert_includes(error.message, "digits and dots")
  end

  def test_app_lookup_uses_supported_bundle_id_filter_only
    selector = TestFlightBuildNumberSelector.new(env: {})
    captured = []

    selector.define_singleton_method(:fetch_paginated_json) do |path, params|
      captured << [path, params]
      [
        {
          "id" => "app-123",
          "attributes" => {
            "bundleId" => "com.anthonyarmijo.hermex"
          }
        }
      ]
    end

    assert_equal(
      "app-123",
      selector.send(:app_id_for_bundle_id, "com.anthonyarmijo.hermex")
    )

    assert_equal("/v1/apps", captured.first.first)
    assert_equal("com.anthonyarmijo.hermex", captured.first.last.fetch("filter[bundleId]"))
    refute_includes(captured.first.last.keys, "filter[platform]")
  end

  def test_jwt_uses_raw_es256_signature_format
    key = OpenSSL::PKey::EC.generate("prime256v1")

    Tempfile.create("app-store-connect-key") do |file|
      file.write(key.to_pem)
      file.flush

      selector = TestFlightBuildNumberSelector.new(
        env: {
          "APP_STORE_CONNECT_KEY_ID" => "KEY123",
          "APP_STORE_CONNECT_ISSUER_ID" => "00000000-0000-0000-0000-000000000000",
          "APP_STORE_CONNECT_KEY_PATH" => file.path
        },
        now: Time.at(1_700_000_000)
      )

      token_parts = selector.send(:jwt_token).split(".")
      payload = JSON.parse(base64url_decode(token_parts[1]))

      assert_equal(3, token_parts.length)
      assert_equal(20 * 60, payload.fetch("exp") - payload.fetch("iat"))
      assert_equal(64, base64url_decode(token_parts[2]).bytesize)
    end
  end

  private

  def base64url_decode(value)
    padding = (4 - (value.length % 4)) % 4
    Base64.urlsafe_decode64(value + ("=" * padding))
  end
end
