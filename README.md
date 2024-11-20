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
