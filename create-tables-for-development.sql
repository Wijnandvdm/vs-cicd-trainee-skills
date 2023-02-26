DROP TABLE IF EXISTS [dbo].[responses]
DROP TABLE IF EXISTS [dbo].[questions]
DROP TABLE IF EXISTS [dbo].[trainees]
DROP TABLE IF EXISTS [dbo].[respondents]

-- Create Dim Table trainees
CREATE TABLE trainees (
  trainee_id INT IDENTITY
  ,trainee_name NVARCHAR(200) 
);

-- Create Dim Table questions
CREATE TABLE questions (
  question_id INT IDENTITY
  ,ms_forms_question_id NVARCHAR(200) 
  ,question NVARCHAR(1000) 
  ,category NVARCHAR(200)
  ,start_date DATETIME2
  ,end_date DATETIME2
  ,is_current INT
);

-- Create Dim Table respondents
CREATE TABLE respondents (
  respondent_id INT IDENTITY
  ,respondent_name NVARCHAR(200) 
);

-- Create Fact Table responses
CREATE TABLE responses (
  response_id INT IDENTITY
  ,question_id INT
  ,respondent_id INT
  ,trainee_id INT 
  ,score INT
  ,submit_date DATETIME2
);