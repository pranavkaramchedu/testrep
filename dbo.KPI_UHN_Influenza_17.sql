SET ANSI_NULLS ON
SET QUOTED_IDENTIFIER ON


CREATE proc [dbo].[KPI_UHN_Influenza_17]
As

BEGIN
DECLARE @INFO VARCHAR(8000)
					,	@TRUE BIT = 1
					,	@FALSE BIT = 0
					,	@DB_ID INT = DB_ID()
					,	@LOGID INT = 0
					,	@PROC VARCHAR(500)=OBJECT_SCHEMA_NAME(@@PROCID)+'.'+OBJECT_NAME(@@PROCID)
					,	@PERF_START DATETIME
					,	@PERF_DURATION INT
					,	@PERF_ROW INT
					,	@RC	INT
					;

		EXEC dbo.SP_KPI_UTIL_LOG_EVENT @@PROCID, @DB_ID, @INFO=@INFO, @LOG2ID=@LOGID OUT;
		DECLARE @PROCFULLNAME VARCHAR(500) = DB_NAME()+'.'+@PROC;
		----EXEC dbo.SP_MI_UTIL_SEND_MAIL @PROCFULLNAME, 'STARTED', 1, @ECHO=0; 
	DECLARE @MSG VARCHAR(1000)
	DECLARE @PERF_START_PROC DATETIME 
	DECLARE @PERF_RPS NUMERIC(10,2) 
	DECLARE @ROWS INT 
	DECLARE @PERF_ROWS INT 
	SET @PERF_ROWS = 0 
	SET @PERF_START = GETDATE() 
	SET @PERF_START_PROC = GETDATE() 

BEGIN TRY

-- Shanawaz 10-13-2021  Add Code G8482 to M17 for Numerator , add code G8483 to Exclusion set

Declare @rundate Date=GetDate()
declare @meas_year varchar(4)=Year(Dateadd(month,-2,@rundate))
declare @rootId INT=159


Declare @ce_startdt Date;
Declare @ce_enddt Date;
Declare @ce_vaccinestartdt Date;

Declare @startDate Date;
Declare @enddate date;
Declare @quarter varchar(20)
Declare @reportId INT;
Declare @measure_id varchar(10);
Declare @target INT;
Declare @domain varchar(100);
Declare @subdomain varchar(100);
Declare @measuretype varchar(100);
Declare @measurename varchar(100);
Declare @reporttype varchar(100);

Set @ce_vaccinestartdt=concat(@meas_year-1,'-08-01');
SET @ce_startdt=concat(@meas_year,'-01-01');
SET @ce_enddt=concat(@meas_year,'-12-31');

Set @reporttype='Physician'
Set @measurename='Influenza Vaccination'
--Set @startDate=DATEADD(yy, DATEDIFF(yy, 0,Dateadd(month,-2,GetDate())), 0) 
--Set @enddate=eomonth(Dateadd(month,-2,GetDate()))
--Set @quarter=Concat(Year(@enddate),' - Q',DATEPART(q, @enddate))
set @target=60
Set @domain='Clinical Quality / Wellness and Prevention'
Set @subdomain='Adult & Pediatric Wellness and Prevention'
Set @measuretype='UHN'
Set @measure_id=17



-- Identify Dead Members
Drop table if exists #17_deceasedmembers
Create table #17_deceasedmembers
(
	EMPI varchar(100)
)
Insert into #17_deceasedmembers
select * from deceasedmembers(@rootId,@ce_startdt,@ce_enddt)


-- Identify Members who had a ambulatory visit
drop table if exists #17_visitlist
Create table #17_visitlist
(
	EMPI varchar(100)
)
Insert into #17_visitlist
Select distinct 
	p.EMPI
From Procedures p
left outer Join ClaimLine c on p.CLAIM_ID=c.CLAIM_ID and
							   ISNULL(p.SV_LINE,0)=ISNULL(c.SV_LINE,0) and
							   p.ROOT_COMPANIES_ID=c.ROOT_COMPANIES_ID and
							   p.PROC_DATA_SRC=c.CL_DATA_SRC and
							   p.EMPI=c.EMPI
Where
	p.Root_Companies_Id=@rootId and
	ISNULL(c.POS,'0')!='81' and
	p.PROC_START_DATE between @ce_vaccinestartdt and @ce_enddt and
	p.PROC_CODE in('90945','90947','90951','90952','90953','90954','90955','90956','90957','90958','90959','90960','90961','90962','90963','90964','90965','90966','90967','90968','90969','90970','99202','99203','99204','99205','99212','99213','99214','99215','99241','99242','99243','99244','99245','99304','99305','99306','99307','99308','99309','99310','99315','99316','99324','99325','99326','99327','99328','99334','99335','99336','99337','99341','99342','99343','99344','99345','99347','99348','99349','99350','99381','99382','99383','99384','99385','99386','99387','99391','99392','99393','99394','99395','99396','99397','99401','99402','99403','99404','99411','99412','99429','99512','G0438','G0439')


-- Identify members who are 6 months and older as on the Reporting Month
drop table if exists #17_denominatorset;
Create table #17_denominatorset
(
	EMPI varchar(100),
	MEMBER_ID varchar(100),
	Gender varchar(10),
	Age INT
)
Insert into #17_denominatorset
select distinct
	EMPI_ID
	,Org_Patient_Extension_ID as MEMBER_ID
	,Gender
	,CASE 
		WHEN dateadd(year, datediff (year, Date_of_Birth,eomonth(@ce_enddt)), Date_of_Birth) > eomonth(@ce_enddt) THEN datediff(year, Date_of_Birth, eomonth(@ce_enddt)) - 1
		ELSE datediff(year, Date_of_Birth, eomonth(@ce_enddt))
	END as Age
from open_empi_master o
join #17_visitlist v on o.EMPI_ID=v.EMPI
left outer join #17_deceasedmembers d on o.EMPI_ID=d.EMPI
where o.Root_Companies_ID=@rootId and
	  Datediff(MONTH,Date_of_Birth,@ce_enddt)>=6 and
	  d.EMPI is null




-- Identify Members with Depression Diagnosis in last 2 years
Drop Table if exists #17_procexclusions;
Create Table #17_procexclusions
(
	EMPI varchar(100)
)
Insert into #17_procexclusions
Select distinct
	EMPI
From
(
	Select
		EMPI
	From GetICDPCS(@rootId,'1900-01-01',@ce_enddt,'Bone Marrow Transplant')

	Union all

	Select
		EMPI
	From GetICDPCS(@rootId,'1900-01-01',@ce_enddt,'Immunocompromising Conditions')

	Union all

	Select
		EMPI
	From GetProcedures(@rootId,'1900-01-01',@ce_enddt,'Cochlear Implant')

	Union all

	Select
		EMPI
	From GetProcedures(@rootId,'1900-01-01',@ce_enddt,'Chemotherapy Procedure')

)t1




-- Identify Members with Bipolar Diagnosis in last 1 year
Drop Table if exists #17_diagexclusions;
Create Table #17_diagexclusions
(
	EMPI varchar(100)
)
Insert into #17_diagexclusions
Select distinct
	EMPI
From
(
	Select
		EMPI
	From GetDiagnosis(@rootId,'1900-01-01',@ce_enddt,'Sickle Cell Anemia and HB S Disease')

	Union all

	Select
		EMPI
	From GetDiagnosis(@rootId,'1900-01-01',@ce_enddt,'Encephalopathy Due To Vaccination')

	Union all

	Select
		EMPI
	From GetDiagnosis(@rootId,'1900-01-01',@ce_enddt,'Immunocompromising Conditions')

	Union all

	Select
		EMPI
	From GetDiagnosis(@rootId,'1900-01-01',@ce_enddt,'Cerebrospinal Fluid Leak')

	Union all

	Select
		EMPI
	From GetDiagnosis(@rootId,'1900-01-01',@ce_enddt,'Chemotherapy Encounter')

	Union all

	select distinct 
		d.EMPI 
	from DIAGNOSIS d
	left outer Join CLAIMLINE c on 
		d.CLAIM_ID=c.CLAIM_ID and 
		d.ROOT_COMPANIES_ID=c.ROOT_COMPANIES_ID and 
		d.DIAG_DATA_SRC=c.CL_DATA_SRC and
		d.EMPI=c.EMPI
	where
		d.Root_Companies_ID=@rootId and
		ISNULL(c.POS,'0')!='81' and
		d.DIAG_CODE in('Z91012','Q8901','726708009','724639003','707147002','38096003','T7808XA','T7808XD','T7808XS')
	
)t1

--Identify members with Hospice exclusion
drop table if exists #17_hospicemembers;
CREATE table #17_hospicemembers
(
	EMPI varchar(50)
		
);
Insert into #17_hospicemembers
select distinct EMPI from hospicemembers(@rootId,@ce_startdt,@ce_enddt)

-- Shanawaz : Logic to exclude members who refure vaccination
Drop table if exists #m17_refusalExclusion
select distinct
	EMPI
	into #m17_refusalExclusion
From PROCEDURES
where
	ROOT_COMPANIES_ID=@rootId and
	PROC_CODE='G8483' and
	ISNULL(PROC_STATUS,'EVN')='EVN' and
	PROC_START_DATE between @ce_vaccinestartdt and @ce_enddt





-- Create Exclusion Set
Drop table if exists #17_exclusions
Create Table #17_exclusions
(
	EMPI varchar(100)
)
Insert into #17_exclusions
Select distinct EMPI from(
	
	Select * from #17_procexclusions

	Union all

	Select * from #17_diagexclusions

	Union all

	Select * from #17_hospicemembers

	Union all

	select EMPI from #m17_refusalExclusion
	
)t1



-- Identify Numerator Set
Drop table if exists #17_numeratorset;
Create table #17_numeratorset
(
	EMPI varchar(100),
	Code varchar(20),
	ServiceDate Date
)
Insert into #17_numeratorset
Select distinct 
	* 
from(

		Select 
			p.EMPI
			,p.PROC_CODE
			,p.PROC_START_DATE
		from KPI_ENGINE.dbo.PROCEDURES p
		left outer join CLAIMLINE c on p.CLAIM_ID=c.CLAIM_ID and 
									   ISNULL(p.SV_LINE,0)=ISNULL(c.SV_LINE,0) and 
									   p.PROC_DATA_SRC=c.CL_DATA_SRC and 
									   p.ROOT_COMPANIES_ID=c.ROOT_COMPANIES_ID and
									   p.EMPI=c.EMPI
		where 
			p.Root_Companies_ID=@rootId and 
			ISNULL(PROC_STATUS,'EVN')!='INT' and
			ISNULL(c.POS,'0')!='81' and
			PROC_START_DATE!='' and 
			PROC_START_DATE between @ce_vaccinestartdt and @ce_enddt and 
			PROC_CODE IN
			(
				Select Code from REG.REGISTRY_VALUESET where ROOT_COMPANIES_ID=@rootId and Measure_id=@measure_id and ValueSetName in('Influenza Vaccination','Adult Influenza Vaccine Procedure','Influenza Vaccine Procedure','Influenza Virus LAIV Vaccine Procedure')
			)

	Union All

	Select 
			m.EMPI 
			,m.MEDICATION_CODE
			,m.FILL_DATE
		from KPI_ENGINE.dbo.MEDICATION m
		left outer join CLAIMLINE c on m.CLAIM_ID=c.CLAIM_ID and 
									   m.MED_DATA_SRC=c.CL_DATA_SRC and 
									   m.ROOT_COMPANIES_ID=c.ROOT_COMPANIES_ID and
									   m.EMPI=c.EMPI
		where 
			m.Root_Companies_ID=@rootId and 
			ISNULL(c.POS,'0')!='81' and
			FILL_DATE between @ce_vaccinestartdt and @ce_enddt and 
			MEDICATION_CODE IN
			(
				select code from HDS.VALUESET_TO_CODE where Value_Set_Name='Influenza Immunization'
			)
)t1



-- Get Numerator Details
Drop table if exists #17_num_detail
Create table #17_num_detail
(
	EMPI varchar(100),
	ServiceDate Date,
	Code varchar(50)
)
Insert into #17_num_detail
Select
	EMPI
	,ServiceDate
	,Code
From
(
	Select
		*
		,row_number() over(partition by EMPI order by ServiceDate desc) as rnk
	From #17_numeratorset
)t3
Where rnk=1


-- Get ReportId from Report_Details

	exec GetReportDetail @rundate=@rundate,@rootId=@rootId,@startDate=@startDate output,@enddate=@enddate output,@quarter=@quarter output,@reportId=@reportId output



-- Create the output as required
Drop table if exists #17_dataset
Create Table #17_dataset
(
	EMPI varchar(100),
	Provider_Id varchar(20),
	PCP_NPI varchar(20),
	PCP_NAME varchar(200),
	Practice_Name varchar(200),
	Specialty varchar(100),
	Measure_id varchar(20),
	Measure_Name varchar(100),
	Payer varchar(50),
	PayerId varchar(100),
	MEM_FNAME varchar(100),
	MEM_MName varchar(50),
	MEM_LNAME varchar(100),
	MEM_DOB Date,
	MEM_GENDER varchar(20),
	Enrollment_Status varchar(20),
	Last_visit_date Date,
	Product_Type varchar(50),
	Num bit,
	Den bit,
	Excl bit,
	Rexcl bit,
	Report_Id INT,
	ReportType varchar(20),
	Report_Quarter varchar(20),
	Period_Start_Date Date,
	Period_End_Date Date,
	Root_Companies_Id INT

)
Insert into #17_dataset
select distinct
	d.EMPI
	,a.AmbulatoryPCPNPI as Provider_Id 
	,a.AmbulatoryPCPNPI as PCP_NPI
	,a.AmbulatoryPCPName as PCP_NAME
	,a.AmbulatoryPCPPractice as Practice_Name
	,a.AmbulatoryPCPSpecialty as Specialty
	,@measure_id as Measure_id
	,@measurename as Measure_Name
	,a.DATA_SOURCE as Payer
	,a.PayerId
	,a.MemberFirstName as MEM_FNAME
	,a.MemberMiddleName as MEM_MName
	,a.MemberLastName as MEM_LNAME
	,a.MemberDOB
	,m.Gender as MEM_GENDER
	,a.EnrollmentStatus
	,a.AmbulatoryPCPRecentVisit as Last_visit_date
	,mm.PAYER_TYPE as ProductType
	,0 as Num
	,1 as Den
	,0 as Excl
	,0 as Rexcl
	,@reportId
	,@reporttype as ReportType
	,@quarter as Report_quarter
	,@startDate as Period_start_date
	,@enddate as Period_end_date
	,@rootId
from #17_denominatorset d
join RPT.PCP_ATTRIBUTION a on d.EMPI=a.EMPI and a.ReportId=@reportId
Join open_empi_master m on d.EMPI=m.EMPI_ID
left outer join MEMBER_MONTH mm on d.EMPI=mm.EMPI and mm.MEMBER_MONTH_START_DATE=DATEADD(month, DATEDIFF(month, 0, @enddate), 0)
where a.AssignedStatus='Assigned'


update ds Set num=1 from #17_dataset ds join #17_numeratorset n on ds.EMPI=n.EMPI
update ds Set Rexcl=1 from #17_dataset ds join #17_exclusions n on ds.EMPI=n.EMPI



-- Insert data into Measure Detailed Line
Delete from RPT.MEASURE_DETAILED_LINE where MEASURE_ID=@measure_id and REPORT_ID=@reportId and ROOT_COMPANIES_ID=@rootId;

Insert into RPT.MEASURE_DETAILED_LINE(Provider_Id,PCP_NPI,PCP_NAME,Practice_Name,Specialty,Measure_id,Measure_Name,Payer,PayerId,MEM_FNAME,MEM_MName,MEM_LNAME,MEM_DOB,MEM_GENDER,ENROLLMENT_STATUS,Last_visit_date,Product_Type,Num,Den,Excl,Rexcl,Report_Id,ReportType,Report_Quarter,Period_Start_date,Period_end_Date,Root_Companies_id,EMPI,MEASURE_TYPE,Code,DateofService)
Select Provider_Id,PCP_NPI,PCP_NAME,Practice_Name,Specialty,Measure_id,Measure_Name,Payer,PayerId,MEM_FNAME,MEM_MName,MEM_LNAME,MEM_DOB,MEM_GENDER,Enrollment_Status,Last_visit_date,Product_Type,Num,Den,Excl,Rexcl,Report_Id,ReportType,Report_Quarter,Period_Start_date,Period_end_Date,Root_Companies_id,d.EMPI,@measuretype,Code,ServiceDate
From #17_dataset d
Left outer join #17_num_detail nd on d.EMPI=nd.EMPI
--where Specialty in('General Practice','Family Medicine','Hospitalists','Internal Medicine','Pediatrics')




-- Insert data into Provider Scorecard
Delete from RPT.PROVIDER_SCORECARD  where MEASURE_ID=@measure_id and REPORT_ID=@reportId and ROOT_COMPANIES_ID=@rootId;
Insert into RPT.PROVIDER_SCORECARD(Provider_Id,PCP_NPI,PCP_NAME,Specialty,Practice_Name,Measure_id,Measure_Name,Measure_Title,MEASURE_SUBTITLE,Measure_Type,NUM_COUNT,DEN_COUNT,Excl_Count,Rexcl_Count,Gaps,Result,Target,To_Target,Report_Id,ReportType,Report_Quarter,Period_Start_Date,Period_End_Date,Root_Companies_Id)
Select 
	Provider_Id
	,PCP_NPI
	,PCP_NAME
	,Specialty
	,Practice_Name
	,Measure_id
	,Measure_Name
	,Measure_Title
	,MEASURE_SUBTITLE
	,Measure_Type
	,SUM(Cast(NUM_COUNT as INT)) as NUM_COUNT
	,SUM(Cast(DEN_COUNT as INT)) as DEN_COUNT
	,SUM(Cast(Excl_Count as INT)) as Excl_Count
	,Sum(Cast(Rexcl_count as INT)) as Rexcl_Count
	,sum(Cast(DEN_Excl as INT)) - SUM(Cast(NUM_COUNT as INT)) as Gaps
	,Case
		when SUM(Cast(DEN_Excl as Float))>0 Then Round((SUM(cast(NUM_COUNT as Float))/ISNULL(NULLIF(SUM(Cast(DEN_Excl as Float)),0),1))*100,2)
		else 0
	end as Result
	,@target as Target
	,Case
		when ((SUM(Cast(DEN_Excl as INT)))*(cast(@target*0.01 as float))) - SUM(Cast(NUM_COUNT as INT))>0 Then CEILING(((SUM(Cast(DEN_Excl as INT)))*(cast(@target*0.01 as float))) - SUM(Cast(NUM_COUNT as INT)))
		Else 0
	end as To_Target
	,Report_Id
	,ReportType
	,Report_Quarter
	,Period_Start_Date
	,Period_End_Date
	,Root_Companies_Id
From
(
	Select distinct
		m.EMPI
		,a.NPI as Provider_id
		,a.NPI as PCP_NPI
		,a.Prov_Name as PCP_Name
		,a.Specialty
		,a.Practice as Practice_Name
		,m.Measure_id
		,m.Measure_Name
		,l.measure_Title
		,l.Measure_SubTitle
		,'Calculated' as Measure_Type
		,Case
			when NUM=1 and excl=0 and rexcl=0 Then 1
			else 0
		end as NUM_COUNT
		,DEN as DEN_COUNT
		,Case
			When DEN=1 and Excl=0 and Rexcl=0 Then 1
			else 0
		End as Den_excl
		,Excl as Excl_Count
		,Rexcl as Rexcl_count
		,Report_Id
		,l.ReportType
		,Report_Quarter
		,Period_Start_Date
		,Period_End_Date
		,m.Root_Companies_Id
		,l.Target
	From RPT.MEASURE_DETAILED_LINE m
	Join RPT.ConsolidatedAttribution_Snapshot a on
		m.EMPI=a.EMPI and a.Attribution_Type='Ambulatory_PCP'
	Join RFT.UHN_measuresList l on
		m.Measure_Id=l.measure_id
	Join RFT.UHN_MeasureSpecialtiesMapping s on
		a.Specialty=s.Specialty and
		m.MEASURE_ID=s.Measure_id
	where Enrollment_Status='Active' and
		  a.NPI!='' and
		  m.MEASURE_ID=@measure_id and
		  REPORT_ID=@reportId 
)t1
Group by Provider_Id,PCP_NPI,PCP_NAME,Specialty,Practice_Name,Measure_id,Measure_Name,Measure_Title,MEASURE_SUBTITLE,Report_Id,ReportType,Report_Quarter,Period_Start_Date,Period_End_Date,Root_Companies_Id,Measure_Type,Target


		SET @PERF_ROW = @@ROWCOUNT
		SET @PERF_DURATION = DATEDIFF(MINUTE,@PERF_START,GETDATE());
		EXEC dbo.SP_KPI_UTIL_LOG_EVENT @@PROCID, @DB_ID, 'Enrollment Completed', @PERF_ROW, @DURATION_IN_MIN=@PERF_DURATION, @LOG2ID=@LOGID;
		EXEC dbo.SP_KPI_UTIL_LOG_EVENT @@PROCID, @DB_ID, @LOG2ID=@LOGID, @END_FLAG=1;

END TRY
BEGIN CATCH
		BEGIN
			EXEC dbo.SP_KPI_UTIL_LOG_EVENT @@PROCID, @DB_ID, 'FATAL ERROR', @LOG2ID=@LOGID;
			RAISERROR ('',16,0)
			RETURN 16
        END
	END CATCH
RETURN 0
END


GO
