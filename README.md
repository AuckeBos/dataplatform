# Dataplatform
A project to host a dataplatform for personal data. Built with purely open-source tools, and designed to host on a homeserver. It uses a metadata-driven approach. 

# Documentation-driven development
I usually approach a software challenge by first building the code, and then documenting it. I partly automate writing documentation, using tools like Github Copilot. This way, I can focus on what I like to do: writing software.

In many cases, a lot of time goes into stuff like:
- Workspace setup
- Infrastructure setup
- Repository setup
- Debugging (negative engineering)

While these tasks are similar for many projects, they are often just different-enough to require a lot of manual work for each project. This is not the most challenging (and hence fun) part of a project. Moreover, I have the idea that a lot of this work can be automated, by generating the code using LLMs. I use this project to validate this assumption. I therefor define and apply the concept of document-driven development:

> Documentation-driven development is an approach for building software. We start by documenting how we envision the project. We write the documentation like we would normally: with the goal to explain people how the system works, such that they can use / develop it. We use the same level of detail. Next, we ask LLMs (Github Copilot, Copilot Workspace, ...) to generate the project step-by-step and part-by-part, using this documentation. We also generate tests, and alter the code where needed. 

This approach has several advantages:
- We do not spend any more time on writing docs than we did before, because we write them with the same mindset.
- We are enforced to think about architecture and tools _before_ we start building. 
- We spend less time on building easy and repetitive code.
- We can focus on the more challenging parts of the project.

# Metadata
The dataplatform is metadata driven. This means that all systems, entities and columns are defined in metadata. Each step in the pipeline has access to this metadata, and process data accordingly. The schema of the metadata is not defined in something like jsonschema, but in Pydantic models. The reason for this choice is that we'll need to use Pydantic to load the metadata into objects anyway. Since Pydantic is strongly typed, this directly defines the schema. The metadata itself is defined in json files. The metadata refers to the Pydantic class that is built for it, and the code instantiates it accordingly. The metadata wil use secrets to connect to the systems. The secrets are stored in a secret store, and are retrieved by the metadata loader. Each metadata key that refers to a secret instead of a value, has a value of type object instead of of type string. The object will contain "type":"secret", and "key": "keyname". The metadata loader will retrieve the secret from the secret store, and replace the object with the actual value. The following metadata files are defined:
- systems.json: Defines the systems that are part of the dataplatform. Each system is identified by a 3-letter code, followed by a number in format `01`. A system is defined by some source that we want to ingest and process data for. It contains a name, a description, and a type. The type is used to determine what kind of connector should be used to ingest data. It links directly to a Connector class, which uses a standardized interface to load and store data. The metadata also defines attributes required for the specific connection type, like a url, a username, or a connection string. Therefor, each system type will have a different schema. Different Pydantic models are used, with the same base class. The system type is used to determine which Pydantic model to use. 
- entities.json: Defines the entities that are part of the dataplatform. An entity is usually a table in a source database, or an entity in an API definition. It contains a name, a description, and a system_id. The system_id links to the system that the entity is part of. It also defines the load_type: full or delta. The entity attributes, their types, and primary keys are _not_ defined in the metadata. Instead, this metadata is defined through the Pydantic model of that entity. The Pydantic model also defines the SCD types of the attributes (1 or 2).
- actions.json: Defines the actions that can be performed on triggers. An action is a piece of code that is executed when an event is sent. This metadata defines the action upon which we should act. It also refers the class that contains the logic. During deployment type, we make sure Prefect Actions (using Prefect Deployments) are created accordingly. The connectors / processors contain generic logic to sent events. We define some platform-generic events, like system-layer processed, and entity-layer-processed. The actions refer to these platform-specific events.

While the system grows in features, the metadata will grow as well. More attributes will be added, to guide the logic that processes the data.

During deployment, the metadata is loaded into the database. These are collections in a Mongo database called "metadata" in the mongodb server. The json is pushed to the mongo collections in mode overwrite, using the mongo cli. 

# Auditing
Auditing tables exist to track changes in the data. While Prefect contains a UI and logs, it will not contain info about the contents of the data, like dataset sizes. Moreover, its useful to manage this information in a central database, to be able to query, and create reports. The auditing tables are stored in a postgres database. Postgres is used over Mongo, to be able to use the power of SQL to query the data. Each table in the the audit schema will have at least a batch_id and a batch_timestamp. This uniquely identifiers a batch of new data. These are linked to the prefect flow that ingested the data, but also the flow that processes it. This batch ID, as well as the flow run IDs are added to the data rows in all layers, as system columns. This links each record in the dataplatform to the corresponding audit tables, but also to the prefect flow runs. This creates a full audit trail. 
- system_run: The highest level auditing table. Contains a record for each run of a system. It links to the system, and records timestamps and success/failure. It also indicates numbers like: nr entities succeeded, nr entities failed, nr of entities skipped. 
- system_layer_run: Contains a record for each layer processed for each system. It links to the system_run, and records timestamps and success/failure. It also indicates numbers like: nr entities succeeded, nr entities failed, nr of entities skipped.
- entity_layer_run: The most detailed level of auditing. Contains a record for each entity processed for each layer for each system. It links to the system_layer_run and the system run. Also records timestamps and success/failure. It also records: nr of records in, nr of records inserted, nr of records updated, nr of records deleted.
- cursor: used to record timestamps of runs for systems. It includes start and end. For delta systems (this is defined in the system metadata), we use this table to load the last run timestamp. This timestamp is used by the system-specific connector, to provide it to the source in the source-specific way that it requires. 

# Secrets
We use Hashicorp Vault as a secret store. It runs in a docker container, and we connect to it through the Python sdk. Generally, metadata will refer to a secret key, and the SecretLoader will load the value from the vault. The master key to the vault is stored in an environment variable.

# Triggers
Triggers are used to start a flow. The following triggers will be supported:
- Time-based triggers. A deployment is created for a flow. This deployment will have a time-based trigger, usually a cron expression. The deployment will start the flow at the specified time. Generally the ingestion of a source system is scheduled using this trigger. This flow creates the batch ID and batch timestamp.
- Event-based triggers. A deployment is created for a flow. This deployment will have an event-based trigger. The event will be a prefect event, using Prefect actions. Events can be default events like flow end or flow fail, or a custom event. Generally, we trigger the processing of a batch of data using this trigger. The trigger contains the batch information, used to find the data in the landing zone. 
- Webhook-based triggers. This is a feature of Prefect cloud. Since we host prefect ourselves, we build a custom mechanism for this. We use fastapi to create a webhook endpoint. When called, it will create a custom prefect event. This event is used as a trigger for flows that should support webhook-based triggers. These type of triggers can be used if a source system supports us registering callbacks, to ingest data near-realtime.

# Data Layers
The data flows through the following layers:
- Landingzone. When data is copied from a source system, it is copied as-is to the landing zone. We store it append-only to a table in this zone. Because source data can be complex and nested, one source endpoint might eventually result in multiple entities in the silver layer. When storing data in the landingzone (through the connector), we therefor process systems at once. This means we cannot land data per-entity, but only per-system. Ie the result is one or more entities, which can be complex and/or contain sub entities. There are no restrictions on the data in this layer.
- Bronze. The bronze layer is also append-only, but in a standardized format. The step from landing to bronze is the most complex one. This step will contain specific logic, which will also flatten and split complex objects into multiple entities. Processing data into bronze goes per-entity. However, how an entity should be retrieved from the landing zone differs greatly per entity. It can be an as-is copy from landing, it could be extracting a nested object from a parent, or it could be copying a parent, but dropping nested properties. The logic will not be system-specific, but pattern-specific. When a new pattern of landing->bronze is found, a processor is created for this pattern. The metadata of the bronze (which is also the silver) entity will reference the processor type. This ensures that any future systems returning data in this format, do not require new code. We therefor have a BronzeProcessor for each landing structure type. This processor receives the target entity as parameter. The metadata will define the landing_entity which will contain the data for the bronze entity. The structure-specific processor contains the specific logic to extract the bronze entity from the landing-entity data. 
- Silver. In this layer, we maintain SCD2 history. The bronze-silver entity relationship is one-to-one. There is no flattening or simplifying. The goal of the silver layer is to maintain scd2 history using generic logic.
- Gold. This layer contains business logic. New entities will be created here, usually by combining multiple source entities. It can also use ML models to generate new entities. This layer is not based on metadata, since it contains custom business logic.

The audit tables contain result statuses for the batches. If some entity fails for some layer, this is represented in those layers. When a flow starts, it always checks the audit tables for the given input. If they indicate that some flow is either still running, or was yet successful, the flow will not start. It wil log this, and return. It is possible that some entities should be processed, and some should not. The flow run can indicate to override this, and to force process the data anyway. This would be done by a manual run, to reprocess data. 

To rerun failed pipelines, we have two options:
- Rerun the failed run. We use the prefect UI to rerun the failed run. This will rerun the flow, and all tasks that failed. This is useful if the failure was due to a temporary issue, like a network error.
- Start a new run with the right parameters. This can also be used to rerun specific parts, for example some entity in some layer. 

# Storage
We use two different storage solutions: Mongo and Postgres. Mongo is used to store metadata and data in the landingzone. This is a good fit, since the data is often semi structured and nested. Because we will not query on source data directly, we do not have a requirement of a SQL interface. Because we will want to query on processed data, we use Postgres. This means that we'll often have a flattening step when moving data from landing to bronze. Flattening is done by following defined conventions. For example: a nested attribute is flattened into a column that concatenates nesting levels using underscores.

Because raw data can be complex, and processed data cannot, a raw entity will often need to be transformed into multiple bronze entities. For example: An entity Vehicle in a source system might contain a list of VehicleOptions. In the source entity, this can be represented as a single entity, with an attribute of type list. In the Postgres layer, this entity will be stored in different entities. 

The target entity therefor contains a reference to the landing entity. The structure-specific processor will contain the logic to extract the bronze entity from the landing entity. Moreover, each landing->bronze structure is documenting, explaining both the structure as well as the logic to extract the bronze entity.

# Orchestration
We use Prefect as the orchestration engine for the dataplatform. Prefect allows us to define, schedule, and monitor workflows (flows) and their individual steps (tasks). The following components are part of our orchestration setup:
- Flows: A flow is a complete workflow that defines the sequence of tasks to be executed. Each flow is responsible for a specific part of the data pipeline, such as ingestion, processing, or archiving.
- Tasks: A task is a single unit of work within a flow. Tasks can be anything from data extraction, transformation, loading, or even sending notifications.
- Triggers: Triggers are used to start flows. We support time-based triggers (e.g., cron expressions), event-based triggers (e.g., Prefect events), and webhook-based triggers (custom implementation using FastAPI).
- Actions: Actions are operations performed as part of a flow, such as sending emails or training machine learning models.

We use the Prefect logger throughout the dataplatform to ensure that all operations are logged. This provides visibility into the execution of flows and tasks, helping us identify and troubleshoot issues. Prefect serves as the main entry point for all operations, and the logs generated by flows contain detailed information about the execution, including any errors or warnings.

In the future, we plan to implement alerting based on flow errors and other critical events to ensure timely responses to issues.

Let me write an infrastructure section matching the style and depth of the existing documentation.

# Infrastructure
The dataplatform uses containerization to ensure consistency across development and production environments. We use Docker and Docker Compose as our container orchestration solution, with the following key components:

- A central `docker-compose.yml` file defining all services and their relationships
- A `.env` file containing environment variables shared across containers
- VS Code devcontainer configuration for development environments

The infrastructure setup follows these principles:
- Development and production use the same base container definitions
- All configuration is externalized through environment variables
- Container networking is handled through docker compose service names
- Data persistence is managed through named volumes
- Development containers include additional tooling for debugging and testing

During development, VS Code's Dev Containers extension is used to provide a consistent development environment. This approach:
- Mirrors the production environment exactly
- Provides native IDE integration
- Enables live code reloading during development
- Shares environment variables and networking with other services

For production deployment, we use the same container definitions but without development-specific volumes and tooling. This ensures that:
- Development and production environments remain in sync
- Deployments are reproducible
- Container updates can be automated through watchtower
- Resource limits can be properly defined and enforced

# Data flow
Data flows through the platform, starting at the source system, ending in the gold layer. Each flow makes sure it initializes records in the audit tables as needed, and updates them upon finish (either success or fail). These include the statuses, but also the different counts that are described earlier.

- Landing. Dropping data in the landing zone is usually triggered on a schedule. The prefect flow loads all data for a specific source system, and stores it in one or many tables in the landing zone (mongo). At this stage, we process on the system-level, not on the entity level.  The landingzone flow also generates the batch id and defines the run timestamp. These are stored alongside the data. They are included in the event that will trigger the next steps. This will tell the next steps how to load the source data. 
- Bronze. At this stage, we start processing on the entity level. We trigger based on the event that is created when a batch for the system is landed. This starts a flow for each entity. The entity metadata has a ref to the table in the landing zone. It also refs the structure type that is used to create the entity in bronze from the landing data. The flow will load the data from the landing table, and process it using the structure-specific processor. The result is stored in the bronze table (postgres). This is append-only. It contains the system columns (batch_id, batch_timestamp, flow_run_id, entity_run_id) and the entity columns. 
- Silver. Triggered by the event sent after bronze process succeeds. Loads data from bronze using batch id and run timestamp. All silver processing goes through one generic processor. It applies SCD1 and SCD2 logic in order. The entities define what cols are scd1, and what are scd 2 (scd2) is default. 
- Gold. Entities in this layer are different than those in bronze / silver. In the metadata, the type of the entity is defined (bronze_silver, or gold). For gold entities, each one references a list of entities in the silver layer. The gold processor will load the data from the silver entities, and process it into the gold entity. Each gold entity will have a gold processor, containing logic specifically for that entity.

# Source connectors
Source connectors are code structures to load data from a source system into the landing zone. They are source system specific. For example, there will be one connector for the Bunq API, and one connector for the Nightscount API. The connector uses SDKs to connect to the sources where possible, or otherwise aiohttp or requests to load using REST apis. The connector does not care about entities, but simply dumps the data as is provided by the source, in the landing zone. It reads config info from the system metadata. it makes use of the SecretLoader to load secret data. If there is shared logic, this will be away using the has-a relationship. For example, a REST connector is implemented, which includes logging, error handling and result formatting. If a source system uses REST instead of an API, it will use this REST connector. 

# Actions
The dataplatform also provides operational-like actions. This can trigger actions based on data that is being loaded / received. An example of an action is sending emails, or training ML models. These actions are triggered by events, which will be sent by the proper flow. In the entity metadata, we define if and when an event should be sent. In the action metadata, we define stuff required for the action to be ran, and action type. Again, this metadata refers to the class that contains the logic. 

# Testing
We refrain from deploying any code without unittests. This is partly because we want to force ourselves to learn to always write tests. Ofcourse, we again try to generate the tests, instead of writing them ourselves. We use an iterative approach:
1. Write / generate docs
2. Generate/update code
3. Generate/update tests
4. Step 2 if fails, else done

All logic contains unit tests. Moreover, we have integration tests to test the flow of data through the system. For this purpose, we define a test system. The data of this system is generated. The storage is simple json files. Therefor we also have a json file system type. Integration tests use this test system. Moreover, there are recurring triggers that process the data of this source system on a regular basis, also in production.

We use pytest. Tests are ran locally in VSCode, but also during build. Required to succeed, both unit and integration tests.

# Data Quality
We use Great Expectations to test the quality of our data. Checks are performed after landing, before bronze. Ie this is the first step of the bronze flow. We use generic checks for all data: uniqueness checks, column count checks. The metadata can define extra tests. The metadata can also define min/max counts, but absolute and percentage. These are converted into Great Expectations tests during the bronze flow. If a test fails, the flow fails. This means only that specific entity is not processed, and errors are logged. 

# Libraries
The sections describes what libraries we use for what purposes. It includes links to the docs pages of the libraries. The main goals is to guide the LLM to provide a code base that uses these libraries.
- [Kink](https://pypi.org/project/kink/) for dependency injection.
- [Rye](https://rye.astral.sh/) as package and environment manager. We use Python >= 3.12
- [Ruff](https://pypi.org/project/ruff/) for linting. We also add a VSCode task to run it on the complete base. Ruff check is a mandatory step in the build pipeline.
- [Sqlalchemy](https://www.sqlalchemy.org/) as ORM for bronze+.
- [Alembic](https://alembic.sqlalchemy.org/en/latest/) for migrations of the postgres databases. 
- [Mongoengine](https://docs.mongoengine.org/) as ORM (ODM) for mongo (metadata and landingzone).
- [Pydantic](https://docs.pydantic.dev/latest/) for data validation, but also metadata schemas.
- [Prefect](https://docs.prefect.io/) as orchestration engine.
- [mlflow](https://mlflow.org/) for ML experimentation, (experiment and model) tracking, model versioning and deployment.
- [mlserver](https://mlserver.readthedocs.io/) for model serving.
- [fastapi](https://fastapi.tiangolo.com/) for webhooks. 
- [pytest](https://docs.pytest.org/) for testing.
- [python-dotenv](https://pypi.org/project/python-dotenv/) for loading environment variables from a .env file.

# Deployment
We use Portainer to manage the containers in the compose file. We create a Dockerfile which will include our source code in the image. The development container will use this Dockerfile; it will have a mount to the code on the host. The same container in production will instead reference the public image, which we push to the Docker hub during deployment. A Watchtower container is used to update the containers whenever we push a new image. We use a Traefik reverse proxy as entrypoint and for SSL cert management. For all deployment and/or build steps, we ensure we can both run them locally as well as in the github actions pipelines, using the exact same logic. This means that the actions will run the ps1 scripts that can also be ran locally.
