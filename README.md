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

# Documentation components
The following components will be described before writing any code. 
- Metadata: Where and how is the metadata defined, and how is it used? Where is the metadata stored?
  - Schemas not with jsonschema, but with Pydantic models.
- Auditing: What is audited, where is it stored?
  - Run timestamp and ids as cols to each table
  - generated cols like ids, scd1/2 hashes, key_hashes, created_at, updated_at
- Secrets: Where and how are secrets stored, and how are they retrieved?
  - Some kind of secret store, with a python client to interact with it
- Triggers: What triggers are supported, and how?
  - Time-based triggers
  - Event-based triggers
  - Callback-based triggers
- Storage: What storage solutions are used for what purpose?
  - Mongo
  - Postgres
- Orchestration: What orchestration engine is used?
  - Prefect
- Infrastructure: On what infrastructure should the platform run?
  - Docker & docker compose
- Data layers: What data layers exist?
  - raw, bronze, silver, gold
- Data flow: How does data flow through layers? When and how is data archived and/or deleted?
  - raw: write jsonfiles
  - bronze: docs in mongo
  - silver: scd2 enabled postgres
  - gold: custom business logic, combining source tables
- Source connectors: How is the connector system configured, and how should one approach building a new connector?
  - base classes to load data
  - Implementations using rest apis or sdks
- Data type: What type of data is supported? Include full load and delta loads.
  - full load
  - delta
- Testing: What testing framework and strategy are used, and what types of tests are included?
  - pytest
  - all should be unittested
  - integration tests
- Libraries: An overview of what libraries are used for what purpose.
  - Kink for dependency injection
  - Sqlalchemy for postgres interaction
    - Alembric for migrations
  - Mongoengine for mongo interaction
  - Pydantic for schemas
  - Prefect for orchestration
  - mlflow for experimentation
    - future
  - Secrets store: ?
- Deployment: To what infra and how should the project be deployed?
    - Docker
    - Docker compose
    - Watchtower
    - Traefik
    - Portainer


# Metadata
The dataplatform is metadata driven. This means that all systems, entities and columns are defined in metadata. Each step in the pipeline has access to this metadata, and process data accordingly. The schema of the metadata is not defined in something like jsonschema, but in Pydantic models. The reason for this choice is that we'll need to use Pydantic to load the metadata into objects anyway. Since Pydantic is strongly typed, this directly defines the schema. The metadata itself is defined in json files. The metadata refers to the Pydantic class that is built for it, and the code instantiates it accordingly. The following metadata files are defined:
- systems.json: Defines the systems that are part of the dataplatform. A system is defined by some source that we want to ingest and process data for. It contains a name, a description, and a type. The type is used to determine what kind of connector should be used to ingest data. It links directly to a Connector class, which uses a standardized interface to load and store data. The metadata also defines attributes required for the specific connection type, like a url, a username, or a connection string. Therefor, each system type will have a different schema. Different Pydantic models are used, with the same base class. The system type is used to determine which Pydantic model to use. 
- entities.json: Defines the entities that are part of the dataplatform. An entity is usually a table in a source database, or an entity in an API definition. It contains a name, a description, and a system_id. The system_id links to the system that the entity is part of. It also defines the load_type: full or delta. It also contains a list of columns. Each column has a name, a type, and if required attributes as length and precision. 

While the system grows in features, the metadata will grow as well. More attributes will be added, to guide the logic that processes the data.

During deployment, the metadata is loaded into the database. These are collections in a Mongo database called "metadata" in the mongodb server. The json is pushed to the mongo collections in mode overwrite, using the mongo cli. 

# Auditing
Auditing tables exist to track changes in the data. While Prefect contains a UI and logs, it will not contain info about the contents of the data, like dataset sizes. Moreover, its useful to manage this information in a central database, to be able to query, and create reports. The auditing tables are stored in a postgres database. Postgres is used over Mongo, to be able to use the power of SQL to query the data. Each table in the the audit schema will have at least a run_id and a run_timestamp. This uniquely identifiers a run. These are linked to the prefect flow, to be able to link the run to the flow. This same flow ID is added to the data rows in all layers, as system column. This links each record in the dataplatform to the corresponding audit tables, but also to the prefect flow runs. This creates a full audit trail. 
- system_run: The highest level auditing table. Contains a record for each run of a system. It links to the system, and records timestamps and success/failure. It also indicates numbers like: nr entities succeeded, nr entities failed, nr of entities skipped. 
- system_layer_run: Contains a record for each layer processed for each system. It links to the system_run, and records timestamps and success/failure. It also indicates numbers like: nr entities succeeded, nr entities failed, nr of entities skipped.
- entity_layer_run: The most detailed level of auditing. Contains a record for each entity processed for each layer for each system. It links to the system_layer_run and the system run. Also records timestamps and success/failure. It also records: nr of records in, nr of records inserted, nr of records updated, nr of records deleted.