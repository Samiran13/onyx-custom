# Metadata Included in Indexing Adapters

This document explains what metadata is fetched and included by the indexing adapters when creating `DocMetadataAwareIndexChunk` objects.

## Overview

The adapters enrich `IndexChunk` objects with metadata fetched from PostgreSQL before indexing to Vespa. This metadata is critical for:
- **Access Control**: Determining who can see which chunks
- **Filtering**: Enabling document set and persona-based filtering
- **Ranking**: Influencing search result ordering
- **Multi-tenancy**: Ensuring tenant isolation

## Adapter Types

There are two main adapters:

1. **DocumentIndexingBatchAdapter** - For connector documents
2. **UserFileIndexingAdapter** - For user-uploaded files

## Metadata Components

### 1. Access Control (`DocumentAccess`)

**Location**: ```105:107:backend/onyx/indexing/adapters/document_indexing_adapter.py```

**What it contains**:
- `user_emails`: Set of user email addresses with access to the document
- `user_groups`: Set of user group names with access
- `external_user_emails`: Set of external user emails (Enterprise feature)
- `external_user_group_ids`: Set of external user group IDs (Enterprise feature)
- `is_public`: Boolean indicating if document is publicly accessible

**How it's fetched**:
- **For documents**: `get_access_for_documents()` → queries `Document` table and related access tables
- **For user files**: `get_access_for_user_files()` → queries `UserFile` table and associated `User`

**Purpose**: Used by Vespa to filter search results based on user permissions. Only chunks the user has access to are returned.

**Code Reference**: ```109:177:backend/onyx/access/models.py```

### 2. Document Sets

**Location**: ```108:113:backend/onyx/indexing/adapters/document_indexing_adapter.py```

**What it contains**:
- `document_sets`: Set of document set names (strings) that the document belongs to

**How it's fetched**:
- `fetch_document_sets_for_documents()` → queries through:
  - `Document` → `DocumentByConnectorCredentialPair` → `ConnectorCredentialPair` → `DocumentSet__ConnectorCredentialPair` → `DocumentSet`

**Purpose**: 
- Enables filtering by document sets in personas
- Allows scoping searches to specific document collections
- Used for federated connector filtering

**Note**: User files don't have document sets (always empty set)

**Code Reference**: ```676:743:backend/onyx/db/document_set.py```

### 3. User Projects

**Location**: ```114:117:backend/onyx/indexing/adapters/user_file_indexing_adapter.py```

**What it contains**:
- `user_project`: List of project IDs (integers) associated with the user file

**How it's fetched**:
- `fetch_user_project_ids_for_user_files()` → queries `UserFile` table and related project associations

**Purpose**: 
- Links user files to specific projects
- Enables project-based filtering and organization
- Used for user file management features

**Note**: Only used for user files, not connector documents (always empty list for documents)

### 4. Boost Score

**Location**: ```142:146:backend/onyx/indexing/adapters/document_indexing_adapter.py```

**What it contains**:
- `boost`: Integer value that influences ranking (positive = higher rank, negative = lower rank)

**How it's fetched**:
- Retrieved from `context.id_to_boost_map` which is populated during document preparation
- Defaults to `DEFAULT_BOOST` if not specified

**Purpose**: 
- Influences search result ranking at query time
- Allows manual boosting of important documents
- Not included in aggregated boost calculation (legacy reasons)

**Note**: User files always use `DEFAULT_BOOST` (indexed only once)

### 5. Aggregated Chunk Boost Factor

**Location**: ```148:148:backend/onyx/indexing/adapters/document_indexing_adapter.py```

**What it contains**:
- `aggregated_chunk_boost_factor`: Float value representing chunk-level boost (currently: information content score)

**How it's calculated**:
- Computed by `_get_aggregated_chunk_boost_factor()` using information content classification model
- Only calculated if `USE_INFORMATION_CONTENT_CLASSIFICATION` is enabled
- Otherwise defaults to `1.0`

**Purpose**: 
- Represents the information density/quality of the chunk
- Used for ranking chunks by their information content
- Helps surface more informative chunks in search results

### 6. Tenant ID

**Location**: ```147:147:backend/onyx/indexing/adapters/document_indexing_adapter.py```

**What it contains**:
- `tenant_id`: String identifier for multi-tenant isolation

**How it's set**:
- Passed as parameter to the adapter constructor
- Ensures all chunks are tagged with their tenant

**Purpose**: 
- Enables multi-tenant deployments
- Ensures tenant isolation in Vespa
- Required for schema-based multi-tenancy

### 7. Chunk Counts (for tracking, not in chunk metadata)

**Location**: ```115:132:backend/onyx/indexing/adapters/document_indexing_adapter.py```

**What it contains**:
- `doc_id_to_previous_chunk_cnt`: Previous chunk count per document
- `doc_id_to_new_chunk_cnt`: New chunk count per document

**How it's fetched**:
- `fetch_chunk_counts_for_documents()` → queries `Document` table
- New count is calculated from the chunks being indexed

**Purpose**: 
- Used to update document chunk counts in PostgreSQL
- Helps track document changes
- Used for cleanup of old chunks in Vespa

**Note**: This is returned in `BuildMetadataAwareChunksResult` but not stored in the chunk itself

### 8. User File Metadata (UserFileIndexingAdapter only)

**Location**: ```152:171:backend/onyx/indexing/adapters/user_file_indexing_adapter.py```

**What it contains**:
- `user_file_id_to_raw_text`: Combined text content of all chunks for the user file
- `user_file_id_to_token_count`: Token count of the combined content

**How it's calculated**:
- Combines all chunk content for each user file
- Uses LLM tokenizer to count tokens

**Purpose**: 
- Stored in file store for faster retrieval
- Used for user file status updates
- Helps with user file management

## Complete Metadata Structure

The final `DocMetadataAwareIndexChunk` contains:

```python
class DocMetadataAwareIndexChunk(IndexChunk):
    # From IndexChunk (which extends DocAwareChunk)
    - All chunk content, embeddings, etc.
    
    # Added by adapter
    tenant_id: str
    access: DocumentAccess  # Contains user_emails, user_groups, external_*, is_public
    document_sets: set[str]
    user_project: list[int]
    boost: int
    aggregated_chunk_boost_factor: float
```

## Comparison: Document vs User File Adapters

| Metadata | DocumentIndexingBatchAdapter | UserFileIndexingAdapter |
|----------|------------------------------|------------------------|
| **Access Control** | ✅ From `get_access_for_documents()` | ✅ From `get_access_for_user_files()` |
| **Document Sets** | ✅ From `fetch_document_sets_for_documents()` | ❌ Always empty set |
| **User Projects** | ❌ Always empty list | ✅ From `fetch_user_project_ids_for_user_files()` |
| **Boost** | ✅ From `context.id_to_boost_map` | ❌ Always `DEFAULT_BOOST` |
| **Aggregated Boost** | ✅ From information content model | ✅ From information content model |
| **Tenant ID** | ✅ From constructor | ✅ From constructor |
| **Raw Text** | ❌ Not stored | ✅ Combined chunk content |
| **Token Count** | ❌ Not stored | ✅ Calculated token count |

## Database Queries Performed

### DocumentIndexingBatchAdapter

1. **Access Control Query**: 
   - Fetches user emails and public flag from `Document` table
   - May join with access-related tables (Enterprise)

2. **Document Sets Query**:
   - Complex join: `Document` → `DocumentByConnectorCredentialPair` → `ConnectorCredentialPair` → `DocumentSet__ConnectorCredentialPair` → `DocumentSet`
   - Filters for current, non-deleting CC pairs

3. **Chunk Count Query**:
   - Simple query to `Document` table for existing chunk counts

### UserFileIndexingAdapter

1. **Access Control Query**:
   - Queries `UserFile` with joined `User` table
   - Extracts user email from associated user

2. **User Projects Query**:
   - Queries project associations for user files

3. **Chunk Count Query**:
   - Queries `UserFile` table for existing chunk counts

4. **Token Calculation**:
   - Combines chunk content and uses LLM tokenizer

## When Metadata is Fetched

Metadata is fetched in the `build_metadata_aware_chunks()` method, which is called:

1. **After embeddings are generated** (chunks are `IndexChunk` objects)
2. **Within document lock** (to prevent race conditions)
3. **Just before indexing to Vespa** (ensures latest metadata)

This timing ensures:
- Access control is up-to-date
- Document sets reflect current associations
- No stale metadata is indexed
- Race conditions are minimized

## Code References

- **DocumentIndexingBatchAdapter**: ```86:159:backend/onyx/indexing/adapters/document_indexing_adapter.py```
- **UserFileIndexingAdapter**: ```97:195:backend/onyx/indexing/adapters/user_file_indexing_adapter.py```
- **DocMetadataAwareIndexChunk Model**: ```94:135:backend/onyx/indexing/models.py```
- **DocumentAccess Model**: ```109:177:backend/onyx/access/models.py```
- **Access Fetching**: ```59:98:backend/onyx/access/access.py```
- **Document Sets Fetching**: ```676:743:backend/onyx/db/document_set.py```

