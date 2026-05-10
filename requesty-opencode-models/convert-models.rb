#!/usr/bin/env ruby
# frozen_string_literal: true

# Converts models.json (Requesty API format) into an
# OpenCode-compatible opencode.json provider configuration.
#
# Usage:
#   ruby convert-models.rb [models.json] [opencode.json]
#
# Defaults:
#   Input:   models.json  (in the same directory)
#   Output:  opencode.json

require "json"

INPUT_FILE  = ARGV[0] || File.join(__dir__, "models.json")
OUTPUT_FILE = ARGV[1] || File.join(__dir__, "opencode.json")

PROVIDER_ID   = "requesty-extra"
PROVIDER_NAME = "Requesty-Extra"
PROVIDER_NPM  = "@ai-sdk/openai-compatible"
BASE_URL      = "https://router.requesty.ai/v1"

# ---------------------------------------------------------------------------
# Helper methods
# ---------------------------------------------------------------------------

# Prices in models.json are per token (e.g. 1.25e-6 = $1.25/1M tokens).
# OpenCode cost expects price per million tokens as a number.
def price(value)
  return nil if value.nil? || value.zero?
  value * 1_000_000
end

# Generates a human-readable display name from the model ID.
# e.g. "anthropic/claude-sonnet-4-20250514" -> "Claude Sonnet 4 20250514"
#      "google/gemini-2.5-pro" -> "Gemini 2.5 Pro"
def humanize_id(id)
  # Strip the provider prefix (everything before the first /)
  name = id.include?("/") ? id.split("/", 2).last : id
  # Strip region suffixes like @europe-west4
  name = name.split("@").first
  # Replace dashes with spaces, title-case
  name.gsub("-", " ").gsub(/\b([a-z])/) { $1.upcase }
end

# Determines input modalities based on model flags.
def input_modalities(model)
  mods = ["text"]
  mods << "image" if model["supports_vision"]
  mods
end

# Determines output modalities.
def output_modalities(model)
  mods = ["text"]
  mods << "image" if model["supports_image_generation"]
  mods
end

# ---------------------------------------------------------------------------
# Main logic
# ---------------------------------------------------------------------------

raw = File.read(INPUT_FILE)
data = JSON.parse(raw)

models_list = data["data"]
abort "No models found in #{INPUT_FILE}." if models_list.nil? || models_list.empty?

# Only use chat API models (if api field is present)
chat_models = models_list.select { |m| m["api"].nil? || m["api"] == "chat" }

opencode_models = {}

chat_models.each do |m|
  model_id = m["id"]
  next if model_id.nil? || model_id.empty?

  entry = {}

  # Display name
  if m["description"] && !m["description"].empty? && m["description"] != "N/A"
    # Use humanized model ID as display name
    entry["name"] = humanize_id(model_id)
  else
    entry["name"] = humanize_id(model_id)
  end

  # Capability flags
  entry["reasoning"]  = true if m["supports_reasoning"]
  entry["tool_call"]  = true if m["supports_tool_calling"]
  entry["attachment"]  = true if m["supports_vision"]

  # Cost
  cost = {}
  cost["input"]       = price(m["input_price"])   if price(m["input_price"])
  cost["output"]      = price(m["output_price"])  if price(m["output_price"])
  cost["cache_write"] = price(m["caching_price"]) if price(m["caching_price"])
  cost["cache_read"]  = price(m["cached_price"])  if price(m["cached_price"])
  entry["cost"] = cost unless cost.empty?

  # Limits
  limit = {}
  limit["context"] = m["context_window"]    if m["context_window"]&.positive?
  # Output is mandatory
  limit["output"]  = m["max_output_tokens"].to_i
  entry["limit"] = limit unless limit.empty?

  # Modalities
  in_mods  = input_modalities(m)
  out_mods = output_modalities(m)
  if in_mods.length > 1 || out_mods.length > 1
    entry["modalities"] = {
      "input"  => in_mods,
      "output" => out_mods
    }
  end

  opencode_models[model_id] = entry
end

# ---------------------------------------------------------------------------
# Build OpenCode configuration
# ---------------------------------------------------------------------------

config = {
  "$schema"  => "https://opencode.ai/config.json",
  "provider" => {
    PROVIDER_ID => {
      "npm"    => PROVIDER_NPM,
      "name"   => PROVIDER_NAME,
      "options" => {
        "baseURL" => BASE_URL,
        "apiKey" => "{env:REQUESTY_API_KEY}"
      },
      "models" => opencode_models
    }
  }
}

json_output = JSON.pretty_generate(config)
File.write(OUTPUT_FILE, json_output + "\n")

puts "Conversion complete: #{chat_models.size} models -> #{OUTPUT_FILE}"
puts "Provider: #{PROVIDER_ID} (#{BASE_URL})"
