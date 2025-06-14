# Spore Protocol API Documentation
# OpenAPI 3.0 Specification

openapi: 3.0.3
info:
  title: Spore Protocol API
  description: |
    # Spore Protocol API Documentation
    
    The Spore Protocol API provides comprehensive access to biological organism simulation, 
    blockchain interactions, and real-time data streaming capabilities.
    
    ## Base URLs
    - Production: `https://api.sporeprotocol.io`
    - Staging: `https://api-staging.sporeprotocol.io`
    - WebSocket: `wss://stream.sporeprotocol.io`
    
    ## Authentication
    
    The API uses API keys for authentication. Include your API key in the `X-API-Key` header:
    ```
    X-API-Key: sk_live_your_api_key_here
    ```
    
    ## Rate Limiting
    
    Rate limits are based on your API tier:
    - **Hobbyist**: 50,000 requests/hour
    - **Professional**: 500,000 requests/hour
    - **Enterprise**: Unlimited
    
    Rate limit information is included in response headers:
    - `X-RateLimit-Limit`: Maximum requests per hour
    - `X-RateLimit-Remaining`: Remaining requests in current window
    - `X-RateLimit-Reset`: Unix timestamp when limit resets
    
    ## Error Handling
    
    The API uses standard HTTP status codes and returns errors in a consistent format:
    ```json
    {
      "error": {
        "code": "INVALID_ORGANISM_ID",
        "message": "The specified organism does not exist",
        "details": {
          "organismId": "invalid-id"
        }
      }
    }
    ```
    
  version: 1.0.0
servers:

  - url: http://localhost:3000/api/v1
    description: Local development

tags:
  - name: Organisms
    description: Manage biological organisms
  - name: Environment
    description: Environmental conditions and factors
  - name: Data
    description: Historical data and analytics
  - name: Predictions
    description: Growth predictions and ML models
  - name: Resources
    description: Resource allocation and management
  - name: Experiments
    description: Scientific experiments and trials
  - name: WebSocket
    description: Real-time data streaming

security:
  - ApiKeyAuth: []

paths:
  /organisms:
    post:
      tags:
        - Organisms
      summary: Create a new organism
      description: Creates a new biological organism with specified parameters
      operationId: createOrganism
      requestBody:
        required: true
        content:
          application/json:
            schema:
              $ref: '#/components/schemas/CreateOrganismRequest'
            examples:
              tomato:
                summary: Create a tomato plant
                value:
                  species: "Tomato"
                  initialBiomass: 100
                  geneticTraits:
                    growthSpeed: 0.8
                    diseaseResistance: 0.7
                    yieldPotential: 0.9
                    adaptability: 0.75
      responses:
        '201':
          description: Organism created successfully
          content:
            application/json:
              schema:
                type: object
                properties:
                  organism:
                    $ref: '#/components/schemas/Organism'
                  message:
                    type: string
                    example: "Organism created successfully"
        '400':
          $ref: '#/components/responses/BadRequest'
        '401':
          $ref: '#/components/responses/Unauthorized'
        '429':
          $ref: '#/components/responses/RateLimitExceeded'

    get:
      tags:
        - Organisms
      summary: List organisms
      description: Retrieve a list of organisms with optional filtering
      operationId: listOrganisms
      parameters:
        - name: species
          in: query
          description: Filter by species
          schema:
            type: string
            example: "Tomato"
        - name: stage
          in: query
          description: Filter by growth stage
          schema:
            $ref: '#/components/schemas/GrowthStage'
        - name: minHealth
          in: query
          description: Minimum health percentage
          schema:
            type: number
            minimum: 0
            maximum: 100
        - name: page
          in: query
          description: Page number (1-based)
          schema:
            type: integer
            minimum: 1
            default: 1
        - name: limit
          in: query
          description: Items per page
          schema:
            type: integer
            minimum: 1
            maximum: 100
            default: 20
        - name: sort
          in: query
          description: Sort field and order
          schema:
            type: string
            enum: [biomass_asc, biomass_desc, health_asc, health_desc, created_asc, created_desc]
            default: created_desc
      responses:
        '200':
          description: List of organisms
          content:
            application/json:
              schema:
                type: object
                properties:
                  organisms:
                    type: array
                    items:
                      $ref: '#/components/schemas/Organism'
                  pagination:
                    $ref: '#/components/schemas/Pagination'

  /organisms/{organismId}:
    get:
      tags:
        - Organisms
      summary: Get organism details
      description: Retrieve detailed information about a specific organism
      operationId: getOrganism
      parameters:
        - $ref: '#/components/parameters/OrganismId'
      responses:
        '200':
          description: Organism details
          content:
            application/json:
              schema:
                $ref: '#/components/schemas/Organism'
        '404':
          $ref: '#/components/responses/NotFound'

    put:
      tags:
        - Organisms
      summary: Update organism
      description: Update organism environmental factors or trigger simulation
      operationId: updateOrganism
      parameters:
        - $ref: '#/components/parameters/OrganismId'
      requestBody:
        required: true
        content:
          application/json:
            schema:
              $ref: '#/components/schemas/UpdateOrganismRequest'
      responses:
        '200':
          description: Organism updated
          content:
            application/json:
              schema:
                $ref: '#/components/schemas/Organism'

    delete:
      tags:
        - Organisms
      summary: Delete organism
      description: Permanently delete an organism
      operationId: deleteOrganism
      parameters:
        - $ref: '#/components/parameters/OrganismId'
      responses:
        '204':
          description: Organism deleted successfully
        '404':
          $ref: '#/components/responses/NotFound'

  /organisms/{organismId}/stage:
    post:
      tags:
        - Organisms
      summary: Update growth stage
      description: Manually transition organism to a new growth stage
      operationId: updateGrowthStage
      parameters:
        - $ref: '#/components/parameters/OrganismId'
      requestBody:
        required: true
        content:
          application/json:
            schema:
              type: object
              required:
                - stage
              properties:
                stage:
                  $ref: '#/components/schemas/GrowthStage'
      responses:
        '200':
          description: Stage updated
          content:
            application/json:
              schema:
                $ref: '#/components/schemas/Organism'
        '400':
          description: Invalid stage transition

  /data/{organismId}/historical:
    get:
      tags:
        - Data
      summary: Get historical data
      description: Retrieve historical time-series data for an organism
      operationId: getHistoricalData
      parameters:
        - $ref: '#/components/parameters/OrganismId'
        - name: startTime
          in: query
          description: Start timestamp (Unix epoch in seconds)
          schema:
            type: integer
            format: int64
        - name: endTime
          in: query
          description: End timestamp (Unix epoch in seconds)
          schema:
            type: integer
            format: int64
        - name: resolution
          in: query
          description: Data point resolution
          schema:
            type: string
            enum: [minute, hourly, daily, weekly]
            default: hourly
        - name: metrics
          in: query
          description: Comma-separated list of metrics to include
          schema:
            type: string
            example: "biomass,health,temperature,humidity"
      responses:
        '200':
          description: Historical data
          content:
            application/json:
              schema:
                type: object
                properties:
                  organismId:
                    type: string
                  dataPoints:
                    type: array
                    items:
                      $ref: '#/components/schemas/DataPoint'
                  resolution:
                    type: string
                  metrics:
                    type: array
                    items:
                      type: string

  /data/{organismId}/predict:
    post:
      tags:
        - Predictions
      summary: Predict organism growth
      description: Generate growth predictions using machine learning models
      operationId: predictGrowth
      parameters:
        - $ref: '#/components/parameters/OrganismId'
      requestBody:
        required: true
        content:
          application/json:
            schema:
              type: object
              properties:
                hours:
                  type: integer
                  minimum: 1
                  maximum: 720
                  default: 24
                  description: Number of hours to predict
                includeConfidenceIntervals:
                  type: boolean
                  default: true
                environmentalScenarios:
                  type: array
                  description: Optional environmental scenarios to test
                  items:
                    $ref: '#/components/schemas/EnvironmentalFactors'
      responses:
        '200':
          description: Growth predictions
          content:
            application/json:
              schema:
                $ref: '#/components/schemas/GrowthPrediction'

  /data/{organismId}/export:
    post:
      tags:
        - Data
      summary: Export organism data
      description: Export organism data in various formats
      operationId: exportData
      parameters:
        - $ref: '#/components/parameters/OrganismId'
      requestBody:
        required: true
        content:
          application/json:
            schema:
              type: object
              properties:
                format:
                  type: string
                  enum: [csv, json, excel, parquet]
                  default: csv
                dateRange:
                  type: object
                  properties:
                    start:
                      type: string
                      format: date-time
                    end:
                      type: string
                      format: date-time
                includeMetadata:
                  type: boolean
                  default: true
      responses:
        '200':
          description: Export link generated
          content:
            application/json:
              schema:
                type: object
                properties:
                  downloadUrl:
                    type: string
                    format: uri
                  expiresAt:
                    type: string
                    format: date-time
                  sizeBytes:
                    type: integer

  /environments:
    post:
      tags:
        - Environment
      summary: Create environment preset
      description: Create a reusable environment configuration
      operationId: createEnvironment
      requestBody:
        required: true
        content:
          application/json:
            schema:
              $ref: '#/components/schemas/CreateEnvironmentRequest'
      responses:
        '201':
          description: Environment created
          content:
            application/json:
              schema:
                $ref: '#/components/schemas/Environment'

  /environments/{environmentId}/apply:
    post:
      tags:
        - Environment
      summary: Apply environment to organisms
      description: Apply an environment preset to one or more organisms
      operationId: applyEnvironment
      parameters:
        - name: environmentId
          in: path
          required: true
          schema:
            type: string
      requestBody:
        required: true
        content:
          application/json:
            schema:
              type: object
              required:
                - organismIds
              properties:
                organismIds:
                  type: array
                  items:
                    type: string
                  minItems: 1
      responses:
        '200':
          description: Environment applied
          content:
            application/json:
              schema:
                type: object
                properties:
                  affectedOrganisms:
                    type: integer
                  results:
                    type: array
                    items:
                      type: object
                      properties:
                        organismId:
                          type: string
                        success:
                          type: boolean
                        error:
                          type: string

  /experiments:
    post:
      tags:
        - Experiments
      summary: Create experiment
      description: Set up a controlled experiment with multiple conditions
      operationId: createExperiment
      requestBody:
        required: true
        content:
          application/json:
            schema:
              $ref: '#/components/schemas/CreateExperimentRequest'
      responses:
        '201':
          description: Experiment created
          content:
            application/json:
              schema:
                $ref: '#/components/schemas/Experiment'

  /experiments/{experimentId}/run:
    post:
      tags:
        - Experiments
      summary: Run experiment
      description: Execute an experiment
      operationId: runExperiment
      parameters:
        - name: experimentId
          in: path
          required: true
          schema:
            type: string
      responses:
        '202':
          description: Experiment started
          content:
            application/json:
              schema:
                type: object
                properties:
                  status:
                    type: string
                    enum: [running, queued]
                  estimatedCompletionTime:
                    type: string
                    format: date-time

  /experiments/{experimentId}/results:
    get:
      tags:
        - Experiments
      summary: Get experiment results
      description: Retrieve results and analysis from a completed experiment
      operationId: getExperimentResults
      parameters:
        - name: experimentId
          in: path
          required: true
          schema:
            type: string
      responses:
        '200':
          description: Experiment results
          content:
            application/json:
              schema:
                $ref: '#/components/schemas/ExperimentResults'

  /chaos/trigger:
    post:
      tags:
        - Organisms
      summary: Trigger chaos event
      description: Trigger a chaos event for testing organism resilience
      operationId: triggerChaosEvent
      requestBody:
        required: true
        content:
          application/json:
            schema:
              type: object
              required:
                - organismId
                - event
              properties:
                organismId:
                  type: string
                event:
                  type: string
                  enum: [pest_outbreak, nutrient_deficiency, heat_wave, power_outage, drought_stress]
                severity:
                  type: number
                  minimum: 0
                  maximum: 1
                  default: 0.5
      responses:
        '200':
          description: Chaos event triggered
          content:
            application/json:
              schema:
                type: object
                properties:
                  message:
                    type: string
                  organism:
                    $ref: '#/components/schemas/Organism'
                  impactAssessment:
                    type: object
                    properties:
                      healthImpact:
                        type: number
                      growthImpact:
                        type: number
                      estimatedRecoveryTime:
                        type: integer

  /stream:
    get:
      tags:
        - WebSocket
      summary: WebSocket endpoint documentation
      description: |
        # WebSocket Streaming API
        
        Connect to real-time organism data streams via WebSocket.
        
        ## Connection URL
        ```
        wss://stream.sporeprotocol.io?organismId={organismId}&apiKey={apiKey}
        ```
        
        ## Message Types
        
        ### Incoming Messages (Server → Client)
        
        #### Initial State
        ```json
        {
          "type": "initial",
          "data": {
            "id": "organism-123",
            "species": "Tomato",
            "stage": "VEGETATIVE",
            "biomass": 2500,
            "health": 92,
            "environmentalFactors": { ... }
          }
        }
        ```
        
        #### Real-time Update
        ```json
        {
          "type": "update",
          "data": {
            "biomass": 2510,
            "health": 91.5,
            "stage": "VEGETATIVE",
            "timestamp": 1679529600000
          }
        }
        ```
        
        #### Error
        ```json
        {
          "type": "error",
          "message": "Invalid organism ID"
        }
        ```
        
        ### Outgoing Messages (Client → Server)
        
        #### Update Environment
        ```json
        {
          "action": "updateEnvironment",
          "data": {
            "temperature": 25,
            "humidity": 70
          }
        }
        ```
        
        #### Subscribe to Additional Organisms
        ```json
        {
          "action": "subscribe",
          "organismIds": ["organism-456", "organism-789"]
        }
        ```
        
      responses:
        '101':
          description: Switching Protocols - WebSocket connection established

components:
  securitySchemes:
    ApiKeyAuth:
      type: apiKey
      in: header
      name: X-API-Key
      description: API key for authentication

  parameters:
    OrganismId:
      name: organismId
      in: path
      description: Unique identifier of the organism
      required: true
      schema:
        type: string
        example: "org_1234567890abcdef"

  schemas:
    CreateOrganismRequest:
      type: object
      required:
        - species
      properties:
        species:
          type: string
          description: Organism species
          example: "Tomato"
          enum: [Tomato, Basil, Cannabis, Oyster Mushroom, Algae]
        initialBiomass:
          type: number
          description: Initial biomass in milligrams
          minimum: 1
          maximum: 10000
          default: 100
        geneticTraits:
          $ref: '#/components/schemas/GeneticTraits'
        environmentalFactors:
          $ref: '#/components/schemas/EnvironmentalFactors'

    UpdateOrganismRequest:
      type: object
      properties:
        environmentalFactors:
          $ref: '#/components/schemas/EnvironmentalFactors'
        simulate:
          type: boolean
          description: Trigger growth simulation
          default: false

    Organism:
      type: object
      properties:
        id:
          type: string
          description: Unique organism identifier
          example: "org_1234567890abcdef"
        species:
          type: string
          example: "Tomato"
        stage:
          $ref: '#/components/schemas/GrowthStage'
        biomass:
          type: number
          description: Current biomass in milligrams
          example: 2500.5
        health:
          type: number
          description: Health percentage (0-100)
          minimum: 0
          maximum: 100
          example: 92.3
        age:
          type: integer
          description: Age in seconds since creation
          example: 604800
        environmentalFactors:
          $ref: '#/components/schemas/EnvironmentalFactors'
        geneticTraits:
          $ref: '#/components/schemas/GeneticTraits'
        lastUpdate:
          type: string
          format: date-time
          description: Last update timestamp
        createdAt:
          type: string
          format: date-time
          description: Creation timestamp

    GrowthStage:
      type: string
      enum:
        - SEED
        - GERMINATION
        - VEGETATIVE
        - FLOWERING
        - FRUITING
        - HARVEST
        - DECAY
      description: Current growth stage of the organism

    EnvironmentalFactors:
      type: object
      properties:
        temperature:
          type: number
          description: Temperature in Celsius
          minimum: -50
          maximum: 100
          example: 22.5
        humidity:
          type: number
          description: Humidity percentage
          minimum: 0
          maximum: 100
          example: 65
        ph:
          type: number
          description: pH level
          minimum: 0
          maximum: 14
          example: 6.8
        lightIntensity:
          type: integer
          description: Light intensity in lux
          minimum: 0
          maximum: 100000
          example: 5000
        co2:
          type: integer
          description: CO2 concentration in ppm
          minimum: 0
          maximum: 5000
          example: 400
        nutrients:
          type: object
          properties:
            nitrogen:
              type: number
              description: Nitrogen level (mg/L)
              example: 100
            phosphorus:
              type: number
              description: Phosphorus level (mg/L)
              example: 50
            potassium:
              type: number
              description: Potassium level (mg/L)
              example: 75

    GeneticTraits:
      type: object
      properties:
        growthSpeed:
          type: number
          description: Growth speed multiplier
          minimum: 0.5
          maximum: 1.5
          default: 1.0
        diseaseResistance:
          type: number
          description: Disease resistance factor
          minimum: 0
          maximum: 1
          default: 0.7
        yieldPotential:
          type: number
          description: Yield potential multiplier
          minimum: 0.5
          maximum: 1.5
          default: 1.0
        adaptability:
          type: number
          description: Environmental adaptability
          minimum: 0
          maximum: 1
          default: 0.8

    DataPoint:
      type: object
      properties:
        timestamp:
          type: integer
          format: int64
          description: Unix timestamp in milliseconds
        biomass:
          type: number
        health:
          type: number
        stage:
          $ref: '#/components/schemas/GrowthStage'
        temperature:
          type: number
        humidity:
          type: number
        ph:
          type: number
        lightIntensity:
          type: integer
        co2:
          type: integer

    GrowthPrediction:
      type: object
      properties:
        organismId:
          type: string
        current:
          $ref: '#/components/schemas/Organism'
        predictions:
          type: array
          items:
            type: object
            properties:
              hour:
                type: integer
              biomass:
                type: number
              health:
                type: number
              stage:
                $ref: '#/components/schemas/GrowthStage'
              confidence:
                type: number
                description: Confidence level (0-1)
        estimatedHarvestTime:
          type: integer
          description: Hours until harvest stage
        optimalConditions:
          $ref: '#/components/schemas/EnvironmentalFactors'

    CreateEnvironmentRequest:
      type: object
      required:
        - name
        - conditions
      properties:
        name:
          type: string
          example: "Optimal Tomato Growth"
        description:
          type: string
        conditions:
          $ref: '#/components/schemas/EnvironmentalFactors'
        tags:
          type: array
          items:
            type: string

    Environment:
      type: object
      properties:
        id:
          type: string
        name:
          type: string
        description:
          type: string
        conditions:
          $ref: '#/components/schemas/EnvironmentalFactors'
        tags:
          type: array
          items:
            type: string
        createdAt:
          type: string
          format: date-time

    CreateExperimentRequest:
      type: object
      required:
        - name
        - species
        - conditions
        - duration
      properties:
        name:
          type: string
          example: "Temperature Impact Study"
        description:
          type: string
        species:
          type: string
        conditions:
          type: array
          minItems: 2
          items:
            type: object
            properties:
              name:
                type: string
              environmentalFactors:
                $ref: '#/components/schemas/EnvironmentalFactors'
        duration:
          type: integer
          description: Duration in hours
          minimum: 1
          maximum: 720
        replications:
          type: integer
          description: Number of replications per condition
          minimum: 1
          maximum: 10
          default: 3

    Experiment:
      type: object
      properties:
        id:
          type: string
        name:
          type: string
        description:
          type: string
        status:
          type: string
          enum: [pending, running, completed, failed]
        species:
          type: string
        conditions:
          type: array
          items:
            type: object
        duration:
          type: integer
        replications:
          type: integer
        createdAt:
          type: string
          format: date-time
        startedAt:
          type: string
          format: date-time
        completedAt:
          type: string
          format: date-time

    ExperimentResults:
      type: object
      properties:
        experimentId:
          type: string
        status:
          type: string
        summary:
          type: object
          properties:
            totalOrganisms:
              type: integer
            successRate:
              type: number
            bestCondition:
              type: string
        conditions:
          type: array
          items:
            type: object
            properties:
              name:
                type: string
              organisms:
                type: integer
              avgBiomass:
                type: number
              avgHealth:
                type: number
              successRate:
                type: number
        statisticalAnalysis:
          type: object
          properties:
            anova:
              type: object
              properties:
                fStatistic:
                  type: number
                pValue:
                  type: number
                significant:
                  type: boolean
        rawData:
          type: array
          items:
            type: object

    Pagination:
      type: object
      properties:
        page:
          type: integer
          example: 1
        limit:
          type: integer
          example: 20
        total:
          type: integer
          example: 150
        totalPages:
          type: integer
          example: 8

    Error:
      type: object
      properties:
        error:
          type: object
          properties:
            code:
              type: string
              example: "INVALID_REQUEST"
            message:
              type: string
              example: "The request parameters are invalid"
            details:
              type: object
              additionalProperties: true

  responses:
    BadRequest:
      description: Bad request
      content:
        application/json:
          schema:
            $ref: '#/components/schemas/Error'
          example:
            error:
              code: "INVALID_REQUEST"
              message: "Invalid request parameters"
              details:
                field: "initialBiomass"
                reason: "Must be between 1 and 10000"

    Unauthorized:
      description: Unauthorized
      content:
        application/json:
          schema:
            $ref: '#/components/schemas/Error'
          example:
            error:
              code: "UNAUTHORIZED"
              message: "Invalid or missing API key"

    NotFound:
      description: Resource not found
      content:
        application/json:
          schema:
            $ref: '#/components/schemas/Error'
          example:
            error:
              code: "NOT_FOUND"
              message: "The requested resource was not found"

    RateLimitExceeded:
      description: Rate limit exceeded
      content:
        application/json:
          schema:
            $ref: '#/components/schemas/Error'
          example:
            error:
              code: "RATE_LIMIT_EXCEEDED"
              message: "API rate limit exceeded"
              details:
                limit: 50000
                remaining: 0
                resetAt: "2024-03-20T15:00:00Z"

---
# Additional Documentation

## SDK Integration Examples

### JavaScript/TypeScript
```javascript
import SporeSDK from '@sporeprotocol/sdk';

const sdk = new SporeSDK({
  apiKey: 'sk_live_your_api_key',
  network: 'mainnet'
});

// Create organism
const organism = await sdk.createOrganism({
  species: 'Tomato',
  initialBiomass: 100,
  growthRate: 50
});

// Stream real-time data
const stream = sdk.streamOrganism(organism.id, {
  onUpdate: (data) => {
    console.log('Biomass:', data.biomass);
    console.log('Health:', data.health);
  }
});

// Predict growth
const prediction = await sdk.predictGrowth(organism.id, 48);
console.log('Harvest in', prediction.harvestTime, 'hours');
```

### Python
```python
from spore_sdk import SporeSDK

sdk = SporeSDK(
    api_key='sk_live_your_api_key',
    network='mainnet'
)

# Create organism
organism = await sdk.create_organism(
    species='Tomato',
    initial_biomass=100,
    growth_rate=50
)

# Get historical data
history = await sdk.get_historical_data(
    organism.id,
    resolution='hourly'
)

# Run experiment
results = await sdk.run_experiment(
    species='Basil',
    conditions=[
        {'temperature': 20, 'humidity': 60},
        {'temperature': 25, 'humidity': 70}
    ],
    duration_hours=168
)
```

### cURL
```bash
# Create organism
curl -X POST https://api.sporeprotocol.io/api/v1/organisms \
  -H "X-API-Key: sk_live_your_api_key" \
  -H "Content-Type: application/json" \
  -d '{
    "species": "Tomato",
    "initialBiomass": 100
  }'

# Get organism
curl https://api.sporeprotocol.io/api/v1/organisms/org_123 \
  -H "X-API-Key: sk_live_your_api_key"

# Stream data (WebSocket)
wscat -c "wss://stream.sporeprotocol.io?organismId=org_123&apiKey=sk_live_your_api_key"
```

## Error Codes Reference

| Code | Description | Resolution |
|------|-------------|------------|
| `INVALID_REQUEST` | Request parameters are invalid | Check request format and parameters |
| `UNAUTHORIZED` | Authentication failed | Verify API key is correct |
| `FORBIDDEN` | Access denied | Check permissions for resource |
| `NOT_FOUND` | Resource not found | Verify resource ID |
| `RATE_LIMIT_EXCEEDED` | Too many requests | Wait for rate limit reset |
| `INVALID_ORGANISM_ID` | Organism ID is invalid | Use valid organism ID |
| `INVALID_STAGE_TRANSITION` | Invalid growth stage transition | Follow valid stage progression |
| `INSUFFICIENT_RESOURCES` | Not enough resources | Allocate required resources |
| `EXPERIMENT_RUNNING` | Experiment already running | Wait for completion |
| `SERVER_ERROR` | Internal server error | Contact support |

## Webhook Events

Configure webhooks to receive real-time notifications:

### Available Events
- `organism.created`
- `organism.stage_changed`
- `organism.health_critical`
- `organism.ready_for_harvest`
- `experiment.completed`
- `resource.depleted`

### Webhook Payload
```json
{
  "event": "organism.stage_changed",
  "timestamp": "2024-03-20T12:00:00Z",
  "data": {
    "organismId": "org_123",
    "previousStage": "VEGETATIVE",
    "newStage": "FLOWERING"
  }
}
```

## Rate Limiting Best Practices

1. **Cache responses** when possible
2. **Use WebSocket streaming** for real-time data instead of polling
3. **Batch operations** when creating multiple organisms
4. **Implement exponential backoff** for retries
5. **Monitor rate limit headers** in responses

## API Versioning

The API uses URL versioning. Current version: `v1`

Future versions will maintain backwards compatibility for at least 6 months after deprecation notice.
