# Document Ingestion Flow Diagram

```mermaid
graph TB
    %% External Data Sources
    EXTERNAL[External Data Sources<br/>Slack, Google Drive, Confluence,<br/>GitHub, SharePoint, etc.]
    
    %% API Entry Points
    API_INGESTION[server/onyx_api/ingestion.py<br/>Direct API Ingestion]
    API_CONNECTOR[server/documents/connector.py<br/>Connector Management API]
    
    %% Connector System
    CONNECTOR_FACTORY[connectors/factory.py<br/>Connector Factory]
    CONNECTOR_RUNNER[connectors/connector_runner.py<br/>Connector Runner]
    CONNECTOR_INTERFACES[connectors/interfaces.py<br/>Connector Interfaces]
    CONNECTOR_REGISTRY[connectors/registry.py<br/>Connector Registry]
    
    %% Background Processing
    CELERY_TASKS[background/celery/tasks/<br/>Celery Task Queue]
    DOCFETCHING[background/celery/tasks/docfetching/<br/>Document Fetching Tasks]
    DOCPROCESSING[background/celery/tasks/docprocessing/<br/>Document Processing Tasks]
    INDEXING_COORD[background/indexing/<br/>Indexing Coordination]
    
    %% File Processing
    FILE_PROCESSING[file_processing/<br/>File Processing Engine]
    TEXT_EXTRACTION[file_processing/extract_file_text.py<br/>Text Extraction]
    IMAGE_ANALYSIS[file_processing/image_summarization.py<br/>Image Analysis]
    UNSTRUCTURED[file_processing/unstructured.py<br/>Advanced Parsing]
    
    %% File Storage
    FILE_STORE[file_store/<br/>File Storage System]
    BATCH_STORAGE[file_store/document_batch_storage.py<br/>Batch Storage]
    
    %% Indexing Pipeline
    INDEXING_PIPELINE[indexing/indexing_pipeline.py<br/>Main Indexing Pipeline]
    CHUNKER[indexing/chunker.py<br/>Document Chunking]
    EMBEDDER[indexing/embedder.py<br/>Vector Embedding]
    VECTOR_INSERT[indexing/vector_db_insertion.py<br/>Vector DB Insertion]
    
    %% Vector Database
    VESPA[document_index/vespa/<br/>Vespa Vector Store]
    VESPA_INDEX[document_index/vespa/index.py<br/>Vespa Index Operations]
    
    %% Database Layer
    DB_COORD[db/indexing_coordination.py<br/>Indexing Coordination]
    DB_ATTEMPTS[db/index_attempt.py<br/>Index Attempt Management]
    DB_MODELS[db/models.py<br/>Database Models]
    
    %% Data Flow - External to Connectors
    EXTERNAL --> CONNECTOR_FACTORY
    API_INGESTION --> INDEXING_PIPELINE
    API_CONNECTOR --> CONNECTOR_FACTORY
    
    %% Connector System Flow
    CONNECTOR_FACTORY --> CONNECTOR_RUNNER
    CONNECTOR_RUNNER --> CONNECTOR_INTERFACES
    CONNECTOR_REGISTRY --> CONNECTOR_FACTORY
    
    %% Background Processing Flow
    CONNECTOR_RUNNER --> CELERY_TASKS
    CELERY_TASKS --> DOCFETCHING
    DOCFETCHING --> DOCPROCESSING
    DOCPROCESSING --> INDEXING_COORD
    
    %% File Processing Flow
    DOCFETCHING --> FILE_PROCESSING
    FILE_PROCESSING --> TEXT_EXTRACTION
    FILE_PROCESSING --> IMAGE_ANALYSIS
    FILE_PROCESSING --> UNSTRUCTURED
    
    %% File Storage Flow
    DOCFETCHING --> FILE_STORE
    FILE_STORE --> BATCH_STORAGE
    BATCH_STORAGE --> DOCPROCESSING
    
    %% Indexing Pipeline Flow
    DOCPROCESSING --> INDEXING_PIPELINE
    INDEXING_PIPELINE --> CHUNKER
    CHUNKER --> EMBEDDER
    EMBEDDER --> VECTOR_INSERT
    
    %% Vector Database Flow
    VECTOR_INSERT --> VESPA
    VESPA --> VESPA_INDEX
    
    %% Database Coordination Flow
    INDEXING_COORD --> DB_COORD
    DB_COORD --> DB_ATTEMPTS
    DB_ATTEMPTS --> DB_MODELS
    
    %% Database Updates
    INDEXING_PIPELINE --> DB_MODELS
    VECTOR_INSERT --> DB_MODELS
    
    %% Styling
    classDef external fill:#ffebee,stroke:#c62828,stroke-width:2px
    classDef api fill:#e3f2fd,stroke:#1565c0,stroke-width:2px
    classDef connector fill:#f3e5f5,stroke:#7b1fa2,stroke-width:2px
    classDef background fill:#fff3e0,stroke:#ef6c00,stroke-width:2px
    classDef processing fill:#e8f5e8,stroke:#2e7d32,stroke-width:2px
    classDef storage fill:#fce4ec,stroke:#ad1457,stroke-width:2px
    classDef indexing fill:#e0f2f1,stroke:#00695c,stroke-width:2px
    classDef database fill:#f1f8e9,stroke:#558b2f,stroke-width:2px
    
    class EXTERNAL external
    class API_INGESTION,API_CONNECTOR api
    class CONNECTOR_FACTORY,CONNECTOR_RUNNER,CONNECTOR_INTERFACES,CONNECTOR_REGISTRY connector
    class CELERY_TASKS,DOCFETCHING,DOCPROCESSING,INDEXING_COORD background
    class FILE_PROCESSING,TEXT_EXTRACTION,IMAGE_ANALYSIS,UNSTRUCTURED processing
    class FILE_STORE,BATCH_STORAGE storage
    class INDEXING_PIPELINE,CHUNKER,EMBEDDER,VECTOR_INSERT,VESPA,VESPA_INDEX indexing
    class DB_COORD,DB_ATTEMPTS,DB_MODELS database
```

## Detailed Processing Steps

### 1. **Document Extraction Phase**
```
External Source → Connector Factory → Connector Runner → Document Batches
```

**Key Folders:**
- `connectors/` - All connector implementations
- `background/celery/tasks/docfetching/` - Document fetching tasks

### 2. **File Processing Phase**
```
Document Batches → File Store → Text Extraction → Image Analysis → Processed Content
```

**Key Folders:**
- `file_processing/` - Text and image processing
- `file_store/` - File storage management

### 3. **Indexing Pipeline Phase**
```
Processed Content → Chunking → Embedding → Vector Database → Database Metadata
```

**Key Folders:**
- `indexing/` - Core indexing pipeline
- `document_index/vespa/` - Vector database operations

### 4. **Coordination and Monitoring**
```
Index Attempts → Progress Tracking → Error Handling → Completion Status
```

**Key Folders:**
- `db/indexing_coordination.py` - Indexing coordination
- `db/index_attempt.py` - Attempt management

## Key Features by Folder

### **Connectors** (`connectors/`)
- **30+ Data Sources**: Slack, Google Drive, Confluence, GitHub, etc.
- **Pluggable Architecture**: Easy to add new connectors
- **Credential Management**: Secure credential handling
- **Checkpointing**: Resume from failures

### **Background Processing** (`background/`)
- **Celery Task Queue**: Asynchronous processing
- **Fault Tolerance**: Error handling and retry logic
- **Progress Tracking**: Real-time status updates
- **Resource Management**: Memory and CPU optimization

### **File Processing** (`file_processing/`)
- **Multi-format Support**: PDF, DOCX, images, code, etc.
- **AI Integration**: Image analysis and summarization
- **Advanced Parsing**: Unstructured.io integration
- **Content Validation**: Quality checks and filtering

### **Indexing Pipeline** (`indexing/`)
- **Smart Chunking**: Semantic document chunking
- **Vector Embeddings**: Multiple embedding models
- **Batch Processing**: Efficient batch operations
- **Context Enhancement**: Rich contextual information

### **Vector Database** (`document_index/`)
- **Vespa Integration**: High-performance vector search
- **Scalable Storage**: Handles large document collections
- **Real-time Updates**: Live index updates
- **Advanced Search**: Complex query capabilities

### **Database Layer** (`db/`)
- **Coordination**: Prevents duplicate processing
- **Progress Tracking**: Detailed status monitoring
- **Metadata Storage**: Document and chunk metadata
- **Error Management**: Comprehensive error tracking

This architecture provides a robust, scalable, and fault-tolerant document ingestion system that can handle diverse data sources and processing requirements.

