/* ============================================================
   Template: incremental MERGE sync with rowversion watermark
   Replace: dbo.SourceTable, dbo.TargetTable, BusinessKey, Col1..ColN,
            'SourceTable_to_TargetTable'
   Assumes: SourceTable has a rowversion column RowVer;
            TargetTable has a LastSyncedUtc datetime2 column
            (drop those lines if it does not).
   ============================================================ */

-- Control and log tables (create once)
IF OBJECT_ID('dbo.SyncWatermark') IS NULL
CREATE TABLE dbo.SyncWatermark (
    SyncName      sysname        NOT NULL PRIMARY KEY,
    LastValue     binary(8)      NOT NULL CONSTRAINT DF_SyncWatermark_LastValue DEFAULT 0x0,
    LastRunUtc    datetime2(3)   NULL,
    RowsInserted  int            NULL,
    RowsUpdated   int            NULL
);

IF OBJECT_ID('dbo.SyncErrorLog') IS NULL
CREATE TABLE dbo.SyncErrorLog (
    ErrorLogId     int IDENTITY(1,1) PRIMARY KEY,
    SyncName       sysname        NOT NULL,
    ErrorNumber    int            NULL,
    ErrorSeverity  int            NULL,
    ErrorState     int            NULL,
    ErrorProcedure nvarchar(128)  NULL,
    ErrorLine      int            NULL,
    ErrorMessage   nvarchar(4000) NULL,
    LoggedUtc      datetime2(3)   NOT NULL DEFAULT SYSUTCDATETIME()
);
GO

CREATE OR ALTER PROCEDURE dbo.usp_Sync_SourceTable_to_TargetTable
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @SyncName  sysname   = N'SourceTable_to_TargetTable';
    DECLARE @FromRv    binary(8);
    DECLARE @ToRv      binary(8) = MIN_ACTIVE_ROWVERSION();   -- upper bound captured first
    DECLARE @Actions   TABLE (ActionName nvarchar(10));

    BEGIN TRY
        IF NOT EXISTS (SELECT 1 FROM dbo.SyncWatermark WHERE SyncName = @SyncName)
            INSERT dbo.SyncWatermark (SyncName) VALUES (@SyncName);

        SELECT @FromRv = LastValue FROM dbo.SyncWatermark WHERE SyncName = @SyncName;

        -- Stage changed rows, one per key (latest wins)
        CREATE TABLE #Changes (
            BusinessKey  int            NOT NULL PRIMARY KEY,
            Col1         nvarchar(100)  NULL,
            Col2         decimal(18,2)  NULL,
            Col3         datetime2(3)   NULL
        );

        INSERT #Changes (BusinessKey, Col1, Col2, Col3)
        SELECT BusinessKey, Col1, Col2, Col3
        FROM (
            SELECT s.BusinessKey, s.Col1, s.Col2, s.Col3,
                   ROW_NUMBER() OVER (PARTITION BY s.BusinessKey ORDER BY s.RowVer DESC) AS rn
            FROM dbo.SourceTable AS s
            WHERE s.RowVer >  @FromRv
              AND s.RowVer <  @ToRv
        ) AS x
        WHERE x.rn = 1;

        BEGIN TRANSACTION;

        MERGE dbo.TargetTable WITH (HOLDLOCK) AS t
        USING #Changes AS s
            ON t.BusinessKey = s.BusinessKey
        WHEN MATCHED AND EXISTS (SELECT s.Col1, s.Col2, s.Col3
                                 EXCEPT
                                 SELECT t.Col1, t.Col2, t.Col3)   -- NULL-safe change test
            THEN UPDATE SET
                 t.Col1 = s.Col1,
                 t.Col2 = s.Col2,
                 t.Col3 = s.Col3,
                 t.LastSyncedUtc = SYSUTCDATETIME()
        WHEN NOT MATCHED BY TARGET
            THEN INSERT (BusinessKey, Col1, Col2, Col3, LastSyncedUtc)
                 VALUES (s.BusinessKey, s.Col1, s.Col2, s.Col3, SYSUTCDATETIME())
        OUTPUT $action INTO @Actions (ActionName);

        -- Advance watermark in the same transaction as the data
        UPDATE dbo.SyncWatermark
           SET LastValue    = @ToRv,
               LastRunUtc   = SYSUTCDATETIME(),
               RowsInserted = (SELECT COUNT(*) FROM @Actions WHERE ActionName = N'INSERT'),
               RowsUpdated  = (SELECT COUNT(*) FROM @Actions WHERE ActionName = N'UPDATE')
         WHERE SyncName = @SyncName;

        COMMIT TRANSACTION;
    END TRY
    BEGIN CATCH
        IF XACT_STATE() <> 0 ROLLBACK TRANSACTION;

        INSERT dbo.SyncErrorLog (SyncName, ErrorNumber, ErrorSeverity, ErrorState,
                                 ErrorProcedure, ErrorLine, ErrorMessage)
        VALUES (@SyncName, ERROR_NUMBER(), ERROR_SEVERITY(), ERROR_STATE(),
                ERROR_PROCEDURE(), ERROR_LINE(), ERROR_MESSAGE());

        THROW;   -- let the Agent job report failure
    END CATCH
END
GO
