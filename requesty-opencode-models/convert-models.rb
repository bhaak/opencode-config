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

PROVIDER_ID   = "requestyextra"
PROVIDER_NAME = "Requesty-Extra"
PROVIDER_PACKAGE = "@opencode/ai/providers/openai-compatible"
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
def model_name(model)
  id = model['id']
  # Strip the provider prefix (everything before the first /)
  if id.include?("/")
    provider_prefix, name = id.split("/", 2)
  else
    raise "No provider: #{id}"
  end

  # Replace dashes with spaces, title-case
  name = "#{name} (#{provider_prefix})"
  name = name.gsub("-", " ").gsub(/\b([a-z])/) { $1.upcase }

  # Fix some name
  name.gsub!(/^Gpt /, 'GPT ') if name.match(/^Gpt /)
  name.gsub!('Deepinfra', 'DeepInfra') if name.include?('Deepinfra')
  name.gsub!('Deepseek', 'DeepSeek') if name.include?('Deepseek')
  name.gsub!('Openai', 'OpenAI') if name.include?('Openai')

  name
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
# Integration into ~/.config/opencode/opencode.json or ~/.opencode/opencode.json
# ---------------------------------------------------------------------------
def integrate_into_config(new_provider_data)
  possible_paths = [
    File.expand_path("~/.config/opencode/opencode.json"),
    File.expand_path("~/.opencode/opencode.json")
  ]

  config_path = possible_paths.find { |path| File.exist?(path) }
  return unless config_path

  config = JSON.parse(File.read(config_path))
  config["providers"] ||= {}

  # Ensure we only update/add the requesty-extra provider
  config["providers"][PROVIDER_ID] = new_provider_data[PROVIDER_ID]
  config["providers"].delete("requesty-extra")
  config["provider"]&.delete(PROVIDER_ID)
  config["provider"]&.delete("requesty-extra")
  config.delete("provider") if config["provider"]&.empty?

  File.write(config_path, JSON.pretty_generate(config) + "\n")
  puts "Updated #{config_path}"
end

# ---------------------------------------------------------------------------
# Download models.json if missing
# ---------------------------------------------------------------------------

MODELS_URL = "https://router.requesty.ai/v1/models"

unless File.exist?(INPUT_FILE)
  puts "Downloading models.json from #{MODELS_URL} ..."
  begin
    require "open-uri"
    content = URI.open(MODELS_URL).read
    File.write(INPUT_FILE, content)
    puts "Saved to #{INPUT_FILE}"
  rescue => e
    abort "Failed to download models.json: #{e.message}"
  end
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
  entry["name"] = model_name(m)

  # Capabilities
  entry["capabilities"] = {
    "tools" => !!m["supports_tool_calling"],
    "input" => input_modalities(m),
    "output" => output_modalities(m)
  }

  # Cost
  cost = {}
  cost["input"]       = price(m["input_price"]) || 0
  cost["output"]      = price(m["output_price"]) || 0
  cache = {}
  cache["write"] = price(m["caching_price"]) if price(m["caching_price"])
  cache["read"]  = price(m["cached_price"])  if price(m["cached_price"])
  cost["cache"] = cache unless cache.empty?
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

opencode_models = opencode_models.sort.to_h

# ---------------------------------------------------------------------------
# Build OpenCode configuration
# ---------------------------------------------------------------------------

provider_config = {
  "package" => PROVIDER_PACKAGE,
  "name"   => PROVIDER_NAME,
  "env" => ["REQUESTY_API_KEY"],
  "settings" => {
    "baseURL" => BASE_URL,
  },
  "models" => opencode_models
}

config = {
  "$schema"  => "https://opencode.ai/config.json",
  "providers" => {
    PROVIDER_ID => provider_config
  }
}

json_output = JSON.pretty_generate(config)
File.write(OUTPUT_FILE, json_output + "\n")

# Integrate into ~/.config/opencode/opencode.json if existing
integrate_into_config({ PROVIDER_ID => provider_config })

puts "Conversion complete: #{chat_models.size} models -> #{OUTPUT_FILE}"
puts "Provider: #{PROVIDER_ID} (#{BASE_URL})"
