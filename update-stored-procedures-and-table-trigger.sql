-- STORED PROCEDURES
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

-- Stored procedure to insert records
CREATE OR ALTER PROCEDURE [dbo].[InsertQuestions]
    (
        @QuestionBody NVARCHAR(MAX)
    )
AS
BEGIN
    INSERT INTO questions(ms_forms_question_id,question,category,start_date, end_date, is_current)
    SELECT 
        ms_forms_question_id -- extracted from JSON
        ,question -- extracted from JSON
        ,category -- extracted from JSON
        ,CONVERT(DATETIME2, start_date, 127) -- extracted from JSON and converted to datetime2 format
        ,NULL -- set end_date to NULL
        ,1 -- set is_current to 1
    FROM OPENJSON ( @QuestionBody, '$.questions' ) WITH(
            ms_forms_question_id    NVARCHAR(200)       '$.id'
            ,question               NVARCHAR(1000)      '$.title'
            ,category               NVARCHAR(200)       '$.subtitle'
            ,start_date             NVARCHAR(200)       '$.modifiedDate'
        ) as questions
    WHERE question <> 'Wat is de naam van de trainee? (Voornaam tussenvoegsel Achternaam)' AND question <> 'Wat is uw naam? (Voornaam tussenvoegsel Achternaam)'
END
GO

CREATE OR ALTER PROCEDURE [dbo].[InsertResponses]
    (
        @QuestionBody NVARCHAR(MAX)
        ,@ResponseBody NVARCHAR(MAX)
    )
AS
BEGIN
    -- RESPONDENTS Retrieve ms_forms_question_id for respondent name question
    DECLARE @RespondentQuestionId NVARCHAR(200) = (SELECT JSON_VALUE(value, '$.id') FROM OPENJSON(@QuestionBody, '$.questions') WHERE JSON_VALUE(value, '$.title') = 'Wat is uw naam? (Voornaam tussenvoegsel Achternaam)')
    -- RESPONDENTS Retrieve respondent name from @RespondeBody by filtering on @RespondentQuestionId
    DECLARE @RespondentName NVARCHAR(MAX) = CONVERT(NVARCHAR(MAX), JSON_VALUE(@ResponseBody, CONCAT('$."', @RespondentQuestionId, '"')))

    -- RESPONDENTS Insert the respondent into the respondents table
    INSERT INTO respondents (respondent_name)
    SELECT @RespondentName
    WHERE NOT EXISTS (SELECT 1 FROM respondents WHERE respondent_name = @RespondentName)

    -- RESPONDENTS Get the ID of the inserted row and set @RespondentId to this ID
    DECLARE @RespondentId INT = (SELECT respondent_id FROM respondents WHERE respondent_name = @RespondentName)

    -- TRAINEES Retrieve ms_forms_question_id for trainee name question
    DECLARE @TraineeQuestionId NVARCHAR(200) = (SELECT JSON_VALUE(value, '$.id') FROM OPENJSON(@QuestionBody, '$.questions') WHERE JSON_VALUE(value, '$.title') = 'Wat is de naam van de trainee? (Voornaam tussenvoegsel Achternaam)')

    -- TRAINEES Retrieve trainee name from @RespondeBody by filtering on @TraineeQuestionId
    DECLARE @TraineeName NVARCHAR(MAX) = CONVERT(NVARCHAR(MAX), JSON_VALUE(@ResponseBody, CONCAT('$."', @TraineeQuestionId, '"')))
    
    -- TRAINEES Insert trainee into trainees table
    INSERT INTO trainees (trainee_name)
    SELECT @TraineeName
    WHERE NOT EXISTS (SELECT 1 FROM trainees WHERE trainee_name = @TraineeName)

    -- TRAINEES Get the ID of the inserted row and set @TraineeId to this ID
    DECLARE @TraineeId INT = (SELECT trainee_id FROM trainees WHERE trainee_name = @TraineeName)

    -- Parse the JSON to get the submitDate
    DECLARE @SubmitDate DATETIME2(0) = CONVERT(DATETIME2(0), JSON_VALUE(@ResponseBody, '$.submitDate'), 0)

    -- Create new JSON for part without responder and submitDate
    DECLARE @QuestionJson NVARCHAR(MAX) = @ResponseBody
    
    -- Remove responder and submitDate keys
    SET @QuestionJson = JSON_MODIFY(@QuestionJson, '$.responder', NULL)
    SET @QuestionJson = JSON_MODIFY(@QuestionJson, '$.submitDate', NULL)

    -- Insert the responses into the responses table
    INSERT INTO responses (
        question_id
        ,respondent_id
        ,trainee_id
        ,submit_date
        ,score
        )
    SELECT 
        q.question_id
        ,@RespondentId
        ,@TraineeId
        ,@SubmitDate
        ,CONVERT(INT, x.[Value])
    FROM OPENJSON(@QuestionJson, '$') AS x
    INNER JOIN questions q ON q.ms_forms_question_id = x.[Key]
    COLLATE DATABASE_DEFAULT -- Specified collation to conform to the database
    WHERE q.is_current = 1
END
GO

CREATE OR ALTER PROCEDURE CheckAverageScoreToday
AS
BEGIN
  SELECT q.question_id, t.trainee_name, AVG(r.score) AS average_score
  FROM responses r
  JOIN trainees t ON r.trainee_id = t.trainee_id
  JOIN (SELECT DISTINCT question_id FROM responses) q ON r.question_id = q.question_id
  WHERE CONVERT(DATE, r.submit_date) = CONVERT(DATE, GETDATE())
  GROUP BY q.question_id, t.trainee_name
  HAVING AVG(r.score) < 2;
END;

-- TABLE TRIGGER
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE OR ALTER TRIGGER [dbo].[SCDTrigger] ON [dbo].[questions]
INSTEAD OF INSERT
AS
BEGIN
    SET NOCOUNT ON;

    INSERT INTO [dbo].[questions] (
        ms_forms_question_id,
        question,
        category,
        start_date,
        end_date,
        is_current
    )
    SELECT 
        i.ms_forms_question_id,
        i.question,
        i.category,
        GETDATE(),
        NULL,
        1
    FROM inserted i
    LEFT JOIN [dbo].[questions] q ON q.ms_forms_question_id = i.ms_forms_question_id AND q.is_current = 1
    WHERE q.question IS NULL OR q.question <> i.question OR q.category <> i.category;

    UPDATE [dbo].[questions] SET end_date = GETDATE(), is_current = 0
    FROM [dbo].[questions] q
    INNER JOIN inserted i ON q.ms_forms_question_id = i.ms_forms_question_id
    WHERE q.is_current = 1 AND (q.question <> i.question OR q.category <> i.category);

END;
GO
ALTER TABLE [dbo].[questions] ENABLE TRIGGER [SCDTrigger]
GO
