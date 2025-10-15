# This configuration tells Active Model Serializers to convert attribute keys
# from snake_case (e.g., bid_credits) to lowerCamelCase (e.g., bidCredits)
# in the final JSON output.

# Set the adapter to :json to ensure key transformations are applied.
ActiveModelSerializers.config.adapter = :json
