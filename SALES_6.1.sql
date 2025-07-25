USE [BNW-MS]
GO
/****** Object:  StoredProcedure [PetrolStationTransfer].[ImportDialogXmlDataSALES_v6.1]    Script Date: 22.07.2025 12:05:36 ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
ALTER PROCEDURE [PetrolStationTransfer].[ImportDialogXmlDataSALES_v6.1]
	@UniCustomerID smallint,
	@PetrolStationID int,
	@ContentXml xml,
	@ImportedBatchID int,
	@ProcessUserID smallint
WITH RECOMPILE
AS
BEGIN
	SET NOCOUNT ON;
	SET XACT_ABORT ON;

	DECLARE @ModuleID tinyint,
			@ErrorMessage nvarchar(MAX)
	SET @ModuleID = Logging.GetModuleIDByProcID(@@PROCID)

	EXEC Logging.InsertInfoToLog @ModuleID, @ProcessUserID, 'Started'

	BEGIN TRY
		DECLARE @Handle int,
				@MaxSaleID bigint,
				@SaleRejectLowerLimit tinyint,
				@SaleRejectUpperLimit tinyint,
				@ClosedLowerLimit datetime2(3),
				@ClosedUpperLimit datetime2(3),
				@ValidationMessage nvarchar(MAX),
				@DialogSequenceNumber smallint,
				@DialogDateTime datetime2(2),
				@LastSequenceNumber smallint,
				@SapTransferErrorTypeID tinyint,
				@PetrolStationActivationDate date,
				@IsFranchise bit,
				@DofoLocalArticleGoodsNumber varchar(9),
				@PetrolStationTypeID char(1)

		DECLARE @ToEmails nvarchar(MAX),
				@ToCcEmails nvarchar(MAX),
				@ToBccEmails nvarchar(MAX),
				@Subject nvarchar(100),
				@Body nvarchar(MAX),
				@PSNumber varchar(3),
				@BenzinaEmail nvarchar(MAX)

		SET @BenzinaEmail = Security.GetSettingsValue('SapTransfer.NotificationBenzina.Email')

		SELECT @IsFranchise = CASE WHEN PSO.Acronym = 'DOFO' THEN 1 ELSE 0 END
		FROM PetrolStation.PetrolStation PS
			INNER JOIN PetrolStation.PetrolStationOwnership PSO ON PSO.ID = PS.PetrolStationOwnershipID

		IF (@IsFranchise = 1)
			SET @DofoLocalArticleGoodsNumber = UniCustomer.GetUniCustomerSettingsValue('Catman.Goods.DoFoLocalArticle', @UniCustomerID)

		IF (CHARINDEX(';', @BenzinaEmail) > 0)
		BEGIN
			SET @ToEmails = LEFT(@BenzinaEmail, CHARINDEX(';', @BenzinaEmail) - 1)
			SET @ToBccEmails = RIGHT(@BenzinaEmail, LEN(@BenzinaEmail) - CHARINDEX(';', @BenzinaEmail))
		END
		ELSE
		BEGIN
			SET @ToEmails = @BenzinaEmail
			SET @ToBccEmails = NULL
		END

		SET @ToCcEmails = Security.GetSettingsValue('SapTransfer.NotificationUnicode.Email')

		-- prazdny retezec neprojde, NULL ano
		IF (@ToCcEmails = '')
			SET @ToCcEmails = NULL

		SELECT @PetrolStationActivationDate = CAST(Created AS date) 
		FROM PetrolStation.BnzRollOutedPetrolStation
		WHERE PetrolStationID = @PetrolStationID

		DECLARE @Shift table (
			PetrolStationID int,
			NodeId bigint,
			Number smallint,
			Date date,
			PosNumber tinyint,
			Opened datetime2(0),
			OpenedBy smallint,
			Closed datetime2(0),
			ClosedBy smallint,
			PRIMARY KEY (NodeId)
		)

		DECLARE @ShiftCash table (
			ShiftNodeId bigint,
			ClientAppCurrencyID char(3),
			OpeningAmount decimal(12,3),
			ClosingAmount decimal(12,3),

			DBCurrencyID char(3)
		)

		-- transform table variables into temp tables to introduce indexing for later joins
		IF OBJECT_ID('tempdb..#Sale') IS NOT NULL
			DROP TABLE #Sale;

		CREATE TABLE #Sale (
			PetrolStationID int,
			ExternalId int,
			PaymentOrder tinyint,
			AdditionalCardExternalNumber int,
			AuthorizationTypeExternalId tinyint,
			BonusCardExternalNumber int,
			BonusCardTypeExternalId varchar(8),
			ClientAppCurrencyID char(3),
			ImportedBatchID int,
			InvoiceCardExternalNumber int,
			PaymentTypeExternalId varchar(8),
			CardTypeExternalId varchar(8),
			CouponTypeExternalId varchar(12),
			CouponExternalId varchar(15),
			Number smallint,
			PosNumber tinyint,
			Closed datetime2(3),
			ReceiptNumber varchar(25),
			ReceiptGrossAmount decimal(12,3),
			PaymentGrossAmount decimal(12,3),
			CardTrack varchar(80),
			BonusCardTrack varchar(80),
			AdditionalCardTrack varchar(80),
			CouponNumber bigint,
			EloadingNumber varchar(30),
			PaymentCouponSerialNumber varchar(30),
			TransactionId varchar(12),
			Authorized datetime2(3),
			AuthorizationCode varchar(12),
			CardExpiration varchar(6),
			Km decimal(8,1),
			DriverId varchar(30),
			Licenceplate varchar(30),
			IsInternalConsumption bit,

			AdditionalCardTypeExternalId varchar(8),
			ReceiptModificationTypeExternalId tinyint,
			ReceiptTypeExternalId tinyint,
			ShiftNumber smallint,
			ShiftDate date,
			CancelType tinyint,
			CardOwnerAddress varchar(50),
			CardOwnerName varchar(30),
			CouponBarcode varchar(14),
			CouponHash varchar(30),
			CouponNominalValue decimal(9,3),
			Coupons decimal(9,3),
			CouponSecondaryId varchar(30),
			CustomerCity nvarchar(60),
			CustomerCountry nvarchar(30),
			CustomerIdentificationNumber varchar(20),
			CustomerName nvarchar(100),
			CustomerNumber int,
			CustomerStreet nvarchar(100),
			CustomerTaxNumber varchar(20),
			CustomerZip varchar(10),
			DailySettlementDate date,
			ExchangeRate decimal(12,6),
			FiscalNumber varchar(100),
			GreenCustomerNumber int,
			Hash varchar(30),
			LoyaltyBurnTransactionId varchar(30),
			LoyaltyEarnTransactionId varchar(30),
			Note varchar(50),
			OrderNumber int,
			PaymentGrossAmountByCustomer decimal(12,3),
			PaymentPart decimal(9,8),
			PartnerIdentificationNumber varchar(15),
			PinStatus varchar(20),
			PosUserName nvarchar(100),
			PosUserNumber smallint,
			ReferencedSaleExternalId int,
			ReferencedSaleReceiptNumber nvarchar(50),
			ShellFleetId varchar(20),
			TableNumber smallint,
			TerminalBatchNumber int,
			TerminalId varchar(12),
			VipCustomerName nvarchar(20),
			VipCustomerNumber int,
			VipRequestId int,
			IsCardManual bit,
			IsDccTransaction bit,
			IsKioskSale bit,
			IsLocalCustomer bit,
			IsMobilePayment bit,
			IsOptSale bit,
			IsPriorCanceledSale bit,
			IsVipDiscountOnline bit,

			DBAdditionalCardID int,
			DBAuthorizationTypeID tinyint,
			DBBonusCardID int,
			DBBonusPaymentTypeGroupID varchar(7),
			DBCurrencyID char(3),
			DBInvoiceCardID int,
			DBPaymentTypeGroupID varchar(7),
			DBAdditionalPaymentTypeGroupID varchar(7),
			DBReceiptModificationTypeID tinyint,
			DBReceiptTypeID tinyint,
			IsCancel bit,
			IsReturn bit,
			IsUpdateEnabled bit
		)
		CREATE CLUSTERED INDEX IDX_Sale_ExternalId_PaymentOrder ON #Sale(ExternalId, PaymentOrder);
		CREATE NONCLUSTERED INDEX IDX_Sale_PetrolStationID ON #Sale(PetrolStationID);
		CREATE NONCLUSTERED INDEX IDX_Sale_CustomerNumber ON #Sale(CustomerNumber);

		IF OBJECT_ID('tempdb..#SaleItem') IS NOT NULL
			DROP TABLE #SaleItem;

		CREATE TABLE #SaleItem (
			SaleExternalId int,
			[Order] smallint,
			CardTermGroupNumber smallint,
			CouponTypeExternalId varchar(12),
			CouponExternalId varchar(15),
			FuelTankNumber tinyint,
			GoodsNumber varchar(9),
			OperationModeExternalId tinyint,
			EanCode varchar(14),
			Quantity decimal(10,4),
			GrossPrice decimal(9,3),
			NetAmount decimal(12,3),
			GrossAmount decimal(12,3),
			VatRate decimal(5,2),
			TotalDiscount decimal(12,3),
			AverageCostAmount decimal(12,3),
			CouponNumber bigint,
			CouponExpiration date,
			DispenserNumber tinyint,
			NozzleNumber tinyint,

			ExciseTaxUnitExternalId varchar(8),
			AgencySupplierNumber int,
			PromotionNumber int,
			AlternativeVatCode varchar(2),
			FuelTemperature decimal(4, 2),
			PurchasePrice decimal(9,3),
			NetAmountWithoutDiscount decimal(12,3),
			GrossAmountWithoutDiscount decimal(12,3),
			PromotionDiscount decimal(12,3),
			BankCardDiscount decimal(12,3),
			BankCardDiscountProfile int,
			CarWashNumber int,
			CarWashProgram int,
			CarWashTransactionID int,
			CarWashAdditionalInfoTypeID int,
			CarWashAdditionalInfoValue varchar(2000),
			CustomerDiscount decimal(12,3),
			CustomerDiscountProfile int,
			CustomerCentralDiscount decimal(12,3),
			CustomerCentralDiscountProfile int,
			CustomerCentralDiscountCompensation decimal(12,3),
			VipDiscount decimal(12,3),
			VipDiscountProfile int,
			VipDiscountProfileName nvarchar(50),
			Nomenclature bigint,
			ExciseTaxRate decimal(10,4),
			ExciseTaxAmount decimal(13,4),
			CouponHash varchar(30),
			ChargeType varchar(8) NULL,
			ChargeCardNumber varchar(50) NULL,
			ChargeApprovalCode varchar(20) NULL,
			Charged datetime2(2) NULL,
			PromoAuthorizationCode varchar(20) NULL,
			PromoAuthorizationCodeType varchar(20) NULL,
			IsCouponOptBound bit,
			IsPriceEanScanned bit,
			IsTandem bit,
			CouponSerialNumber varchar(30),
			IsOnline bit,

			DBCardTerminalGroupID smallint,
			DBCouponPaymentTypeGroupID varchar(7),
			DBFuelTankID int,
			DBGoodsID int,
			DBOperationModeID tinyint,
			DBExciseTaxUnitID tinyint,
			DBAgencySupplierID int,
			DBPromotionID int,
			ExciseTaxRateFactor smallint,
			IsFuel bit,
			IsRounding bit
		)
		CREATE CLUSTERED INDEX IDX_SaleItem_SaleExternalId_Order ON #SaleItem(SaleExternalId, [Order]);
		CREATE NONCLUSTERED INDEX IDX_SaleItem_GoodsID ON #SaleItem(DBGoodsID);
		CREATE NONCLUSTERED INDEX IDX_SaleItem_VatRate ON #SaleItem(VatRate);

		DECLARE @LoyaltySale table (
			SaleExternalId int,
			LoyaltyCardID int,
			LoyaltyCustomerID int,
			CardNumber varchar(30),
			IsOnline bit,
			IsVirtualCard bit,

			DBLoyaltyCardID int,
			DBLoyaltyCustomerID int
		)

		DECLARE @LoyaltySaleItem table (
			SaleExternalId int,
			SaleItemOrder smallint,
			AccrualProfileID int,
			RedemptionDiscountTypeSecondaryExternalId tinyint,
			RedemptionProfileID int,
			AccruedPoints decimal(13,4),
			RedeemedPoints decimal(13,4),
			Discount decimal(12,3),
			CompensationAmount decimal(12,3),

			DBAccrualProfileID int,
			DBRedemptionDiscountTypeID tinyint,
			DBRedemptionProfileID int
		)

		DECLARE @AccruedLoyaltyPoint table (
			SaleExternalId int,
			[Order] tinyint,
			LoyaltyPointTypeID tinyint,
			PromotionNumber int,
			CardNumber varchar(30),
			Quantity decimal(9,4),
			IsOnline bit,

			DBLoyaltyPointTypeID tinyint,
			DBPromotionID int
		)

		DECLARE @UnknownCode table (
			SaleExternalId int,
			[Order] tinyint,
			Scanned datetime2(0),
			Code varchar(200)
		)

		DECLARE @IssuedCoupon table (
			SaleExternalId int,
			CouponTypeExternalId varchar(12),
			CouponExternalId varchar(15),
			Number int,
			Barcode varchar(14),
			NominalValue decimal(9,3),
			Expiration date,
			SecondaryId varchar(30),
			RuleNumber int,

			DBCouponPaymentTypeGroupID varchar(7)
		)

		DECLARE @AppliedPromotion table (
			SaleExternalId int,
			PromotionNumber int,
			Promotions smallint,

			DBPromotionID int
		)

		DECLARE @ReturnedCash table (
			SaleExternalId int,
			ClientAppCurrencyID char(3),
			ExchangeRate decimal(12,6),
			Amount decimal(13,4),
			IsTerminalCashback bit,

			DBCurrencyID char(3)
		)

		DECLARE @AccruedSupershopPoint table (
			CardNumber varchar(80),
			TransactionId varchar(50),
			TransactionNumber varchar(50),
			TerminalId int,
			PosId varchar(50),
			TotalPoints int,
			PointsGained int,
			PointsRate int,
			ResponseMessage nvarchar(120)
		)

		DECLARE @DeletedSaleItem table (
			PetrolStationID int,
			GoodsNumber varchar(9),
			ShiftNumber smallint,
			ShiftDate date,
			ExternalId int,
			Deleted datetime2(0),
			PosNumber tinyint,
			EanCode varchar(14),
			Quantity decimal(10,4),
			GrossPrice decimal(9,3),
			GrossAmount decimal(12,3),
			VatRate decimal(5,2),
			AlternativeVatCode varchar(2),

			DBGoodsID int
		)

		DECLARE @CashMovement table (
			PetrolStationID int,
			CardTypeExternalId varchar(8),
			CashMovementTypeExternalId tinyint,
			CashMovementTypeExternalSign smallint,
			ClientAppCurrencyID char(3),
			ShiftNumber smallint,
			ShiftDate date,
			ExternalId int,
			Entered datetime2(0),
			Number int,
			PosNumber tinyint,
			PosUserNumber smallint,
			NetAmount decimal(12,3),
			GrossAmount decimal(12,3),
			VatRate decimal(5,2),
			AlternativeVatCode varchar(2),
			ExchangeRate decimal(12,6),
			CardExtendedInfo varchar(50),
			Note nvarchar(50),
			IsCancel bit,
			IsCashAffected bit,
			IsSaldoAffected bit,
			IsTurnoverAffected bit,

			DBCardPaymentTypeGroupID varchar(7),
			DBCashMovementTypeID tinyint,
			DBCurrencyID char(3)
		)

		DECLARE @CashMovementCoupon table (
			CashMovementExternalId int,
			[Order] tinyint,
			CouponPaymentTypeGroupID varchar(7),
			Number bigint,
			Hash varchar(30),
			GrossAmount decimal(12,3)
		)

		DECLARE @FiscalRegistration table (
			NodeId bigint,
			CashMovementExternalId int,
			SaleExternalId int,
			[Order] tinyint,
			BusinessPremisesId int,
			ReceiptNumber varchar(30),
			ExportedReceiptNumber varchar(30),
			TaxpayerTaxNumber varchar(20),
			AppointingTaxpayerTaxNumber varchar(20),
			GrossAmount decimal(12,3),
			NetAmountExemptFromVat decimal(12,3),
			NetAmountBasicVatRate decimal(12,3),
			NetAmountReducedVatRate decimal(12,3),
			NetAmountSecondReducedVatRate decimal(12,3),
			VatAmountBasicVatRate decimal(12,3),
			VatAmountReducedVatRate decimal(12,3),
			VatAmountSecondReducedVatRate decimal(12,3),
			IntendedSubsequentDrawingGrossAmount decimal(12,3),
			SubsequentDrawingGrossAmount decimal(12,3),
			FiscalIdentificationCode varchar(100),
			TaxpayerSecurityCode varchar(44),
			TaxpayerSignatureCode varchar(344),
			RequestStatus tinyint,
			RequestErrorCode varchar(10),
			RequestErrorMessage nvarchar(150)
		)

		DECLARE @FiscalRegistrationWarning table (
			FiscalRegistrationNodeId bigint,
			Code varchar(10),
			Message nvarchar(150)
		)

		DECLARE @ShiftIDs table (
			NodeId bigint PRIMARY KEY,
			ID int
		)

		DECLARE @UpdatedSaleIDs table (
			ID bigint,
			PaymentOrder tinyint,
			ExternalId int,
			ReceiptModificationTypeID tinyint,
			ReceiptTypeID tinyint,
			CustomerCity nvarchar(60),
			CustomerCountry nvarchar(30),
			CustomerIdentificationNumber varchar(20),
			CustomerName nvarchar(100),
			CustomerStreet nvarchar(100),
			CustomerTaxNumber varchar(20),
			CustomerZip varchar(10),
			GreenCustomerNumber int
		)

		DECLARE @SaleIDs table (
			ExternalId int,
			ID bigint,
			PaymentOrder tinyint,
			PaymentPart decimal(9,8),
			PaymentTypeGroupID varchar(7),
			ClosedDate date,
			PRIMARY KEY (
				ExternalId,
				PaymentOrder
			),
			INDEX IX_SaleIDs (ExternalID, ID, PaymentOrder, PaymentPart, PaymentTypeGroupID, ClosedDate)
		)

		DECLARE @SaleCancelation table (
			SaleID bigint,
			SalePaymentOrder tinyint,
			CanceledSaleID bigint,
			CanceledSalePaymentOrder tinyint,
			ReturnedSaleID bigint,
			ReturnedSalePaymentOrder tinyint,
			INDEX IX_SaleCancelation (SaleID, SalePaymentOrder, CanceledSaleID, CanceledSalePaymentOrder, ReturnedSaleID, ReturnedSalePaymentOrder)
		)

		DECLARE @CashMovementIDs table (
			ExternalId int PRIMARY KEY,
			ID bigint
		)

		DECLARE @RecipeComponent table (
			SaleExternalId int,
			SaleItemOrder smallint,
			AgencySupplierNumber int,
			GoodsNumber varchar(9),
			AverageCostAmount decimal(13, 4),
			Quantity decimal(10, 4),

			DBAgencySupplierID int,
			DBGoodsID int
		)

		DECLARE @MarketingText table (
			SaleExternalId int,
			MarketingTextID int,
			CodeType tinyint,
			CodeValue varchar(20)
		)

		DECLARE @CustomerUpdate table (
			SaleExternalId int,
			SaleNumber smallint,
			PosNumber tinyint,
			SaleClosed datetime2(3),
			CustomerName varchar(100),
			CustomerNumber varchar(20),
			CustomerTaxID varchar(20),
			CustomerAddress varchar(100),
			CustomerCity varchar(60),
			CustomerCountry varchar(30),
			CustomerZip varchar(10)
		)

		DECLARE @FiscalRegistrationUpdate table (
			SaleExternalId int,
			BusinessPremiseNumber int,
			SaleNumber smallint,
			PosNumber tinyint,
			SaleClosed datetime2(3),
			RequestStatus tinyint,
			ReceiptNumberEs varchar(30),
			ReceiptNumberEet varchar(30),
			TaxNumber varchar(20),
			MandatingTaxNumber varchar(20),
			FiscalIdentificationCode varchar(100),
			TaxpayerSecurityCode varchar(44),
			TaxpayerSignatureCode varchar(344),
			ErrorCode varchar(10),
			ErrorMessage varchar(150)
		)

		DECLARE @OptReconciliation table (
			PetrolStationID int,
			UniCustomerID smallint,
			ExternalId int,
			TerminalId varchar(20),
			TerminalTypeId varchar(10),
			PosNumber tinyint,
			Batch int,
			Amount decimal(12, 3),
			StatusNumber tinyint,
			StatusDescription nvarchar(40),
			CloseDate datetime2(3),
			OpenDate datetime2(3),
			[User] nvarchar(20)
		)

		DECLARE @OptBanknote table (
			PetrolStationID int,
			ExternalId int,
			TerminalId varchar(20),
			TerminalTypeId varchar(10),
			PosNumber tinyint,
			CurrencyID char(3),
			NominalValue int,
			[Count] int,
			Amount int,
			DamagedCount int
		)

		EXEC sp_xml_preparedocument @Handle OUTPUT, @ContentXml

		-- Kontrola na poradi dialogu - chyba 4 - MIS_DIA (Missing dialog)
		SELECT
			@DialogSequenceNumber = SequenceNumber,
			@DialogDateTime = DateTime
		FROM OPENXML(@Handle, '/SALES/Dialog')
			WITH (
				SequenceNumber int '@SequenceNumber',
				DateTime datetime2(2) '@Date'
			) TAB

		SELECT @LastSequenceNumber = ISNULL(MAX(SequenceNumber), 0)
		FROM SapTransfer.SaleDialogSequenceLog
		WHERE PetrolStationID = @PetrolStationID

		IF (@DialogSequenceNumber - 1 <> @LastSequenceNumber)
		BEGIN
			SET @ValidationMessage =
				'Sale dialog with SequenceNumber: '
				+ CAST(@DialogSequenceNumber AS nvarchar)
				+ ' is not in the correct order because last processed dialog has SequenceNumber: '
				+ CAST(@LastSequenceNumber AS nvarchar)

			SET @SapTransferErrorTypeID = 4

			RAISERROR(@ValidationMessage, 16, 1)
		END

		-- Kontrola na existenci dialogu DailyCheck za predchozi den ve stavu 1 - OK.
		-- Pokud neni, zastavit dialogy SALES na chybu
		-- Kontroluje se pouze stav DailyCheck z predchoziho dne - jde o stavy z CS. Pokud dojde k chybe na WO, SALES uz je pozastaveny a sem by se nemel dostat.
		DECLARE @DailySettlementDate date,
				@CashMoveDate date,
				@DailyCheckStatusID tinyint

		SELECT @DailySettlementDate = DailySettlementDate
		FROM OPENXML(@Handle, '/SALES/Sale[1]')
			WITH (
				DailySettlementDate date '@DailySettlementDate'
			) TAB

		SELECT @CashMoveDate = CashMoveDate
		FROM OPENXML(@Handle, '/SALES/CashMove[1]')
			WITH (
				CashMoveDate date '@CashMoveDate'
			) TAB

		-- Kontroluji se pouze dialogu SALES obsahujici prodeje nebo hotovostni pohyby pro CS, 
		-- ktere vznikly drive nez je datum prodeje (a maji uz nejaky ukonceny DailyCheck)
		IF (@DailySettlementDate IS NOT NULL OR @CashMoveDate IS NOT NULL) 
		BEGIN
			IF (@PetrolStationActivationDate < ISNULL(@DailySettlementDate, @CashMoveDate))
			BEGIN
				SELECT @DailyCheckStatusID = DailyCheckStatusID
				FROM SapTransfer.DailyCheck
				WHERE PetrolStationID = @PetrolStationID
					AND DailySettlementDate = DATEADD(DAY, -1, ISNULL(@DailySettlementDate, @CashMoveDate))

				IF (@DailyCheckStatusID <> 1 OR @DailyCheckStatusID IS NULL)
				BEGIN
					SET @SapTransferErrorTypeID = CASE WHEN ISNULL(@DailyCheckStatusID, 4) = 3 THEN 1 ELSE 2 END

					SET @ValidationMessage = N'DAILYCHECK for previous day is not OK.'

					RAISERROR (@ValidationMessage, 16, 1)
				END
			END
		END

		-- Parsovani dialogu
		INSERT INTO @Shift (
			PetrolStationID,
			NodeId,
			Number,
			Date,
			PosNumber,
			Opened,
			OpenedBy,
			Closed,
			ClosedBy
		)
		SELECT
			@PetrolStationID,
			TAB.NodeId,
			TAB.Number,
			TAB.Date,
			TAB.PosNumber,
			TAB.Opened,
			TAB.OpenedBy,
			TAB.Closed,
			TAB.ClosedBy
		FROM OPENXML(@Handle, '/SALES/Shift')
			WITH (
				NodeId bigint '@mp:id',
				Number smallint '@ShiftNumber',
				Date date '@ShiftDate',
				PosNumber tinyint '@POSNumber',
				Opened datetime2(0) '@ShiftBegin',
				OpenedBy smallint '@UserBegin',
				Closed datetime2(0) '@ShiftEnd',
				ClosedBy smallint '@UserEnd',

				IsPersonBound bit '@PersonalShift'
			) TAB

		INSERT INTO @ShiftCash (
			ShiftNodeId,
			ClientAppCurrencyID,
			OpeningAmount,
			ClosingAmount,

			DBCurrencyID
		)
		SELECT
			TAB.ShiftNodeId,
			TAB.ClientAppCurrencyID,
			TAB.OpeningAmount,
			TAB.ClosingAmount,

			CUR.CurrencyID
		FROM OPENXML(@Handle, '/SALES/Shift/ShiftCash')
			WITH (
				ShiftNodeId bigint '@mp:parentid',
				ClientAppCurrencyID char(3) '@CurrencyID',
				OpeningAmount decimal(12,3) '@ShiftCashBegin',
				ClosingAmount decimal(12,3) '@ShiftCashEnd'
			) TAB
			LEFT OUTER JOIN PetrolStationTransfer.ImportDialogCurrency CUR ON CUR.ID = TAB.ClientAppCurrencyID

		INSERT INTO #Sale (
			PetrolStationID,
			ExternalId,
			PaymentOrder,
			AdditionalCardExternalNumber,
			AuthorizationTypeExternalId,
			BonusCardExternalNumber,
			BonusCardTypeExternalId,
			ClientAppCurrencyID,
			ImportedBatchID,
			InvoiceCardExternalNumber,
			PaymentTypeExternalId,
			CardTypeExternalId,
			CouponTypeExternalId,
			CouponExternalId,
			Number,
			PosNumber,
			Closed,
			ReceiptNumber,
			ReceiptGrossAmount,
			PaymentGrossAmount,
			CardTrack,
			BonusCardTrack,
			AdditionalCardTrack,
			CouponNumber,
			EloadingNumber,
			PaymentCouponSerialNumber,
			TransactionId,
			Authorized,
			AuthorizationCode,
			CardExpiration,
			Km,
			DriverId,
			Licenceplate,
			IsInternalConsumption,

			AdditionalCardTypeExternalId,
			ReceiptModificationTypeExternalId,
			ReceiptTypeExternalId,
			ShiftNumber,
			ShiftDate,
			CancelType,
			CardOwnerAddress,
			CardOwnerName,
			CouponBarcode,
			CouponHash,
			CouponNominalValue,
			Coupons,
			CouponSecondaryId,
			CustomerCity,
			CustomerCountry,
			CustomerIdentificationNumber,
			CustomerName,
			CustomerNumber,
			CustomerStreet,
			CustomerTaxNumber,
			CustomerZip,
			DailySettlementDate,
			ExchangeRate,
			FiscalNumber,
			GreenCustomerNumber,
			Hash,
			LoyaltyBurnTransactionId,
			LoyaltyEarnTransactionId,
			Note,
			OrderNumber,
			PaymentGrossAmountByCustomer,
			PaymentPart,
			PartnerIdentificationNumber,
			PinStatus,
			PosUserName,
			PosUserNumber,
			ReferencedSaleExternalId,
			ReferencedSaleReceiptNumber,
			ShellFleetId,
			TableNumber,
			TerminalBatchNumber,
			TerminalId,
			VipCustomerName,
			VipCustomerNumber,
			VipRequestId,
			IsCardManual,
			IsDccTransaction,
			IsKioskSale,
			IsLocalCustomer,
			IsMobilePayment,
			IsOptSale,
			IsPriorCanceledSale,
			IsVipDiscountOnline,

			DBAdditionalCardID,
			DBAuthorizationTypeID,
			DBBonusCardID,
			DBBonusPaymentTypeGroupID,
			DBCurrencyID,
			DBInvoiceCardID,
			DBPaymentTypeGroupID,
			DBAdditionalPaymentTypeGroupID,
			DBReceiptModificationTypeID,
			DBReceiptTypeID,
			IsCancel,
			IsReturn,
			IsUpdateEnabled
		)
		SELECT
			@PetrolStationID,
			TAB.ExternalId,
			TAB.PaymentOrder,
			CASE WHEN TAB.IsAdditionalCardCentral = 1 THEN TAB.AdditionalCardExternalNumber ELSE NULL END,
			TAB.AuthorizationTypeExternalId,
			CASE WHEN TAB.IsBonusCardCentral = 1 THEN TAB.BonusCardExternalNumber ELSE NULL END,
			TAB.BonusCardTypeExternalId,
			TAB.ClientAppCurrencyID,
			@ImportedBatchID,
			CASE WHEN TAB.IsInvoiceCardCentral = 1 THEN TAB.InvoiceCardExternalNumber ELSE NULL END,
			TAB.PaymentTypeExternalId,
			TAB.CardTypeExternalId,
			TAB.CouponTypeExternalId,
			TAB.CouponExternalId,
			TAB.Number,
			TAB.PosNumber,
			TAB.Closed,
			--Sale.GetReceiptNumber(@PetrolStationID, TAB.PosNumber, TAB.Closed, TAB.Number),
			TAB.ReceiptNumberES,
			TAB.ReceiptGrossAmount,
			TAB.PaymentGrossAmount,
			TAB.CardTrack,
			TAB.BonusCardTrack,
			TAB.AdditionalCardTrack,
			TAB.CouponNumber,
			TAB.EloadingNumber,
			TAB.PaymentCouponSerialNumber,

			TAB.TransactionId,
			CAST(TAB.Authorized AS datetime2(3)),		-- nacist z XML jako varchar, jinak xml uplatnuje casovou zonu - problem u mobilnich plateb
			TAB.AuthorizationCode,
			TAB.CardExpiration,
			TAB.Km,
			TAB.DriverId,
			TAB.Licenceplate,
			TAB.IsInternalConsumption,

			TAB.AdditionalCardTypeExternalId,
			TAB.ReceiptModificationTypeExternalId,
			TAB.ReceiptTypeExternalId,
			TAB.ShiftNumber,
			TAB.ShiftDate,
			TAB.CancelType,
			TAB.CardOwnerAddress,
			TAB.CardOwnerName,
			TAB.CouponBarcode,
			TAB.CouponHash,
			TAB.CouponNominalValue,
			TAB.Coupons,
			TAB.CouponSecondaryId,
			TAB.CustomerCity,
			TAB.CustomerCountry,
			TAB.CustomerIdentificationNumber,
			TAB.CustomerName,
			TAB.CustomerNumber,
			TAB.CustomerStreet,
			TAB.CustomerTaxNumber,
			TAB.CustomerZip,
			TAB.DailySettlementDate,
			TAB.ExchangeRate,
			TAB.FiscalNumber,
			TAB.GreenCustomerNumber,
			TAB.Hash,
			TAB.LoyaltyBurnTransactionId,
			TAB.LoyaltyEarnTransactionId,
			TAB.Note,
			TAB.OrderNumber,
			TAB.PaymentGrossAmountByCustomer,
			TAB.PaymentPart,
			TAB.PartnerIdentificationNumber,
			TAB.PinStatus,
			NULLIF(TAB.PosUserName,''),
			TAB.PosUserNumber,
			TAB.ReferencedSaleExternalId,
			TAB.ReferencedSaleReceiptNumber,
			TAB.ShellFleetId,
			TAB.TableNumber,
			TAB.TerminalBatchNumber,
			TAB.TerminalId,
			TAB.VipCustomerName,
			TAB.VipCustomerNumber,
			TAB.VipRequestId,
			TAB.IsCardManual,
			TAB.IsDccTransaction,
			TAB.IsKioskSale,
			CASE WHEN TAB.IsBonusCardCentral = 1 OR TAB.IsInvoiceCardCentral = 1  OR (TAB.IsBonusCardCentral = 1 AND TAB.IsInvoiceCardCentral = 1) THEN 0 ELSE 1 END,
			TAB.IsMobilePayment,
			TAB.IsOptSale,
			CASE WHEN TAB.ReferencedSaleExternalId IS NOT NULL THEN TAB.IsPriorCanceledSale ELSE NULL END,
			TAB.IsVipDiscountOnline,

			AddCRD.ID,
			AT.ID,
			BonCRD.ID,
			PT.BonusPaymentTypeGroupID,
			CUR.CurrencyID,
			InvCRD.ID,
			PT.PaymentTypeGroupID,
			PT.AdditionalPaymentTypeGroupID,
			MT.ID,
			RT.ID,
			TAB.IsCancel,
			TAB.IsReturn,
			MT.IsUpdateEnabled
		FROM OPENXML(@Handle, '/SALES/Sale/Payment')
			WITH (
				ExternalId int '../@SaleID',
				PaymentOrder tinyint '@Line',
				AdditionalCardExternalNumber int '@SupplementalCardEvidenceNumber',
				IsAdditionalCardCentral bit '@SupplementalCardIsCentral',
				AuthorizationTypeExternalId tinyint '@PaymentTransOnline',
				BonusCardExternalNumber int '@BonusCardEvidenceNumber',
				IsBonusCardCentral bit '@BonusCardIsCentral',
				BonusCardTypeExternalId varchar(8) '@BonusCardTypeID',
				ClientAppCurrencyID char(3) '@CurrencyID',
				InvoiceCardExternalNumber int '@InvoiceCardEvidenceNumber',
				IsInvoiceCardCentral bit '@InvoiceCardIsCentral',
				PaymentTypeExternalId varchar(8) '@PaymentTypeID',
				CardTypeExternalId varchar(8) '@CardTypeID',
				CouponTypeExternalId varchar(12) '@CouponTypeID',
				CouponExternalId varchar(15) '@CouponID',
				Number smallint '../@SaleNumber',
				PosNumber tinyint '../@SalePosNumber',
				Closed datetime2(3) '../@SaleClose',
				ReceiptNumberES varchar(50) '../@ReceiptNumberES',
				ReceiptGrossAmount decimal(12,3) '../@SaleSum',
				PaymentGrossAmount decimal(12,3) '@PaymentSum',
				CardTrack varchar(80) '@CardTrack',
				BonusCardTrack varchar(80) '@BonusCardTrack',
				AdditionalCardTrack varchar(80) '@SupplementalCardTrack',
				CouponNumber bigint '@PaymentCouponNumber',
				TransactionId varchar(12) '@PaymentTransID',
				Authorized varchar(30) '@PaymentTerminalDateTime',
				AuthorizationCode varchar(12) '@PaymentTerminalAuthCode',
				CardExpiration varchar(6) '@PaymentCardExp',
				Km decimal(8,1) '@PaymentKm',
				DriverId varchar(30) '@PaymentDriverID',
				Licenceplate varchar(30) '@PaymentVehicleRegNo',
				IsInternalConsumption bit '../@IsInternalSale',

				AdditionalCardTypeExternalId varchar(8) '@SupplementalCardTypeID',
				ReceiptModificationTypeExternalId tinyint '../@ChangeDoc',
				ReceiptTypeExternalId tinyint '../@SaleSlipType',
				ShiftNumber smallint '../@ShiftNumber',
				ShiftDate date '../@ShiftDate',
				CancelType tinyint '@PaymentCancelType',
				CardOwnerAddress varchar(50) '@PaymentCardOwnerAddress',
				CardOwnerName varchar(30) '@PaymentCardOwnerName',
				CouponBarcode varchar(14) '@PaymentCouponEAN',
				CouponHash varchar(30) '@PaymentCouponCode',
				CouponNominalValue decimal(9,3) '@CouponNominalValue',
				Coupons decimal(9,3) '@CouponQuantity',
				CouponSecondaryId varchar(30) '@CouponSecID',
				CustomerCity nvarchar(60) '../@SaleCustCity',
				CustomerCountry nvarchar(30) '../@SaleCustCountry',
				CustomerIdentificationNumber varchar(20) '../@SaleCustID',
				CustomerName nvarchar(100) '../@SaleCustName',
				CustomerNumber int '@PaymentCustomer',
				CustomerStreet nvarchar(100) '../@SaleCustAddress',
				CustomerTaxNumber varchar(20) '../@SaleCustTaxID',
				CustomerZip varchar(10) '../@SaleCustZIP',
				DailySettlementDate date '../@DailySettlementDate',
				ExchangeRate decimal(12,6) '@PaymentCurrRation',
				FiscalNumber varchar(100) '../@SaleFiskalNumber',
				GreenCustomerNumber int '../@DirectoryID',
				Hash varchar(30) '../@SaleSlipHash',
				LoyaltyBurnTransactionId varchar(30) '../@LoyaltyBurnTranId',
				LoyaltyEarnTransactionId varchar(30) '../@LoyaltyEarnTranId',
				Note varchar(50) '@PaymentNote',
				OrderNumber int '@PaymentOrderNumber',
				PaymentGrossAmountByCustomer decimal(12,3) '@PaidSum',
				PaymentPart decimal(9,8) '@PaymentPart',
				PartnerIdentificationNumber varchar(15) '../@PartnerID',
				PinStatus varchar(20) '@PaymentPINStatus',
				PosUserName nvarchar(100) '../@SaleUserName',
				PosUserNumber smallint '../@SaleUserNumber',
				ReferencedSaleExternalId int '../@OrigSaleID',
				ReferencedSaleReceiptNumber nvarchar(50) '../@OrigReceiptNumber',
				ShellFleetId varchar(20) '@PaymentShellFleetId',
				TableNumber smallint '../@SaleTableNumber',
				TerminalBatchNumber int '@PaymentTerminalBatchNo',
				TerminalId varchar(12) '@PaymentTerminalID',
				VipCustomerName nvarchar(20) '@VIPCustName',
				VipCustomerNumber int '@VIPCustNumber',
				VipRequestId int '@VIPRequestID',
				IsCardManual bit '@PaymentCardManual',
				IsDccTransaction bit '@DCCTransaction',
				IsKioskSale bit '../@IsKioskSale',
				IsMobilePayment bit '../@IsMobilePayment',
				IsOptSale bit '../@IsOPTSale',
				IsPriorCanceledSale bit '../@OrigSaleSentBefore',
				IsVipDiscountOnline bit '@VIPOnlineDiscountCalc',

				IsCancel bit '../@SaleCanceled',
				IsReturn bit '../@SaleIsGoodsReturn',

				ReceiptCancelTypeExternalId smallint '../@CancelReasonID',
				ReceiptCancelTypeName varchar(50) '../@CancelReasonName',
				SateliteNumber int '../@SaleSatelitNumber',
				FiscalPrinterNumber varchar(30) '../@FiscalPrinterNo',
				FiscalClosed datetime2(0) '../@FiscalClose',
				FiscalQRCode varchar(2048) '../@FiscalQRCode',
				LoyaltyCardPan varchar(50) '../@SDLoyaltyCardPAN',
				ExtendedTransactionId varchar(30) '@PaymentTransIDHOS',
				IsCouponCentral bit '@CouponIsCentral',
				CardHolderNumber tinyint '@CardHolderNumber',
				TerminalDiscountProfile nvarchar(50) '@TermDiscountProfileNumber',
				EloadingNumber varchar(30) '@PaymentTransRefNo',
				PaymentCouponSerialNumber varchar(30) '@PaymentCouponSerialNum'
			) TAB
			CROSS APPLY (
				SELECT
					CASE
						WHEN (TAB.PaymentTypeExternalId = 'PT_BANC'
								AND ISNULL(TAB.CardTypeExternalId, '') = ''
							) THEN 'CT_NULL'
						WHEN (TAB.PaymentTypeExternalId = 'PT_INVC'
								AND ISNULL(TAB.CardTypeExternalId, '') = ''
							) THEN 'CT_NULLI'
							ELSE TAB.CardTypeExternalId
					END AS CardTypeExternalId,
					CASE WHEN (TAB.PaymentTypeExternalId = 'PT_COUP')
						THEN TAB.CouponTypeExternalId
						ELSE NULL
					END AS CouponTypeExternalId,
					CASE WHEN (TAB.PaymentTypeExternalId = 'PT_COUP')
						THEN TAB.CouponExternalId
						ELSE NULL
					END AS CouponExternalId
			) TABS
			CROSS APPLY (
				SELECT
					Sale.GetPaymentTypeGroupIDForSale(TAB.PaymentTypeExternalId, TABS.CardTypeExternalId, TABS.CouponTypeExternalId, TABS.CouponExternalId) AS PaymentTypeGroupID,
					Sale.GetPaymentTypeGroupIDForBonusCard(TAB.BonusCardTypeExternalId) AS BonusPaymentTypeGroupID,
					Sale.GetPaymentTypeGroupIDForAdditionalCard(TAB.AdditionalCardTypeExternalId) AS AdditionalPaymentTypeGroupID
			) PT
			LEFT OUTER JOIN StationCustomer.Card AddCRD ON AddCRD.ExternalNumber = TAB.AdditionalCardExternalNumber
				AND AddCRD.UniCustomerID = @UniCustomerID
			LEFT OUTER JOIN Sale.AuthorizationType AT ON AT.ExternalId = TAB.AuthorizationTypeExternalId
			LEFT OUTER JOIN StationCustomer.Card BonCRD ON BonCRD.ExternalNumber = TAB.BonusCardExternalNumber
				AND BonCRD.UniCustomerID = @UniCustomerID
			LEFT OUTER JOIN PetrolStationTransfer.ImportDialogCurrency CUR ON CUR.ID = TAB.ClientAppCurrencyID
			LEFT OUTER JOIN StationCustomer.Card InvCRD ON InvCRD.ExternalNumber = TAB.InvoiceCardExternalNumber
				AND InvCRD.UniCustomerID = @UniCustomerID
			LEFT OUTER JOIN Sale.ReceiptModificationType MT ON MT.ExternalId = TAB.ReceiptModificationTypeExternalId
			LEFT OUTER JOIN Sale.ReceiptType RT ON RT.ExternalId = TAB.ReceiptTypeExternalId

		INSERT INTO #SaleItem (
			SaleExternalId,
			[Order],
			CardTermGroupNumber,
			CouponTypeExternalId,
			CouponExternalId,
			FuelTankNumber,
			GoodsNumber,
			OperationModeExternalId,
			EanCode,
			Quantity,
			GrossPrice,
			NetAmount,
			GrossAmount,
			VatRate,
			TotalDiscount,
			AverageCostAmount,
			CouponNumber,
			CouponExpiration,
			DispenserNumber,
			NozzleNumber,

			ExciseTaxUnitExternalId,
			AgencySupplierNumber,
			PromotionNumber,
			AlternativeVatCode,
			FuelTemperature,
			PurchasePrice,
			NetAmountWithoutDiscount,
			GrossAmountWithoutDiscount,
			PromotionDiscount,
			BankCardDiscount,
			BankCardDiscountProfile,
			CarWashNumber,
			CarWashProgram,
			CarWashTransactionID,
			CarWashAdditionalInfoTypeID,
			CarWashAdditionalInfoValue,
			CustomerDiscount,
			CustomerDiscountProfile,
			CustomerCentralDiscount,
			CustomerCentralDiscountProfile,
			CustomerCentralDiscountCompensation,
			VipDiscount,
			VipDiscountProfile,
			VipDiscountProfileName,
			Nomenclature,
			ExciseTaxRate,
			ExciseTaxAmount,
			CouponHash,
			ChargeType,
			ChargeCardNumber,
			ChargeApprovalCode,
			Charged,
			PromoAuthorizationCode,
			PromoAuthorizationCodeType,
			IsCouponOptBound,
			IsPriceEanScanned,
			IsTandem,
			CouponSerialNumber,
			IsOnline,

			DBCardTerminalGroupID,
			DBCouponPaymentTypeGroupID,
			DBFuelTankID,
			DBGoodsID,
			DBOperationModeID,
			DBExciseTaxUnitID,
			DBAgencySupplierID,
			DBPromotionID,
			ExciseTaxRateFactor,
			IsFuel,
			IsRounding
		)
		SELECT
			TAB.SaleExternalId,
			TAB.[Order],
			TAB.CardTermGroupNumber,
			TAB.CouponTypeExternalId,
			TAB.CouponExternalId,
			TAB.FuelTankNumber,
			CASE WHEN TAB.GoodsNumber LIKE '01%' THEN @DoFoLocalArticleGoodsNumber ELSE TAB.GoodsNumber END,
			TAB.OperationModeExternalId,
			TAB.EanCode,
			TAB.Quantity,
			TAB.GrossPrice,
			TAB.NetAmount,
			TAB.GrossAmount,
			TAB.VatRate,
			NULLIF(TAB.TotalDiscount, 0.0),
			TAB.AverageCostAmount,
			TAB.CouponNumber,
			TAB.CouponExpiration,
			TAB.DispenserNumber,
			TAB.NozzleNumber,

			TAB.ExciseTaxUnitExternalId,
			TAB.AgencySupplierNumber,
			TAB.PromotionNumber,
			TAB.AlternativeVatCode,
			TAB.FuelTemperature,
			TAB.PurchasePrice,
			TAB.NetAmountWithoutDiscount,
			TAB.GrossAmountWithoutDiscount,
			NULLIF(TAB.PromotionDiscount, 0.0),
			NULLIF(TAB.BankCardDiscount, 0.0),
			TAB.BankCardDiscountProfile,
			TAB.CarWashNumber,
			TAB.CarWashProgram,
			TAB.CarWashTransactionId,
			TAB.CarWashAdditionalInfoTypeId,
			TAB.CarWashAdditionalInfoValue,
			NULLIF(TAB.CustomerDiscount, 0.0),
			TAB.CustomerDiscountProfile,
			NULLIF(TAB.CustomerCentralDiscount, 0.0),
			TAB.CustomerCentralDiscountProfile,
			NULLIF(TAB.CustomerCentralDiscountCompensation, 0.0),
			TAB.VipDiscount,
			TAB.VipDiscountProfile,
			TAB.VipDiscountProfileName,
			TAB.Nomenclature,
			NULLIF(TAB.ExciseTaxRate, 0.0),
			TAB.ExciseTaxAmount,
			TAB.CouponHash,
			TAB.ChargeType,
			TAB.ChargeCardNumber,
			TAB.ChargeApprovalCode,
			TAB.Charged,
			TAB.PromoAuthorizationCode,
			TAB.PromoAuthorizationCodeType,
			TAB.IsCouponOptBound,
			TAB.IsPriceEanScanned,
			TAB.IsTandem,
			TAB.CouponSerialNumber,
			ISNULL(TAB.IsOnline, 0),

			CTG.ID,
			E.CouponPaymentTypeGroupID,
			FT.ID,
			G.ID,
			OM.ID,
			U.ID,
			AGN.ID,
			PV.ID,
			U.ExciseTaxRateFactor,
			G.IsFuel,
			CASE WHEN G.Number = E.RoundingGoodsNumber THEN 1 ELSE 0 END
		FROM OPENXML(@Handle, '/SALES/Sale/SaleItem')
			WITH (
				SaleExternalId int '../@SaleID',
				[Order] smallint '@SaleItemLine',
				CardTermGroupNumber smallint '@CardTermGroup',
				CouponTypeExternalId varchar(12) '@CouponTypeID',
				CouponExternalId varchar(15) '@CouponID',
				FuelTankNumber tinyint '@SaleItemTankNumber',
				GoodsNumber varchar(9) '@GoodsID',
				OperationModeExternalId tinyint '@SaleItemOpMode',
				EanCode varchar(14) '@EAN',
				Quantity decimal(10,4) '@SaleItemQuantity',
				GrossPrice decimal(9,3) '@SaleItemPrice',
				NetAmount decimal(12,3) '@SaleItemNetto',
				GrossAmount decimal(12,3) '@SaleItemSum',
				VatRate decimal(5,2) '@SaleItemTax',
				TotalDiscount decimal(12,3) '@DiscountTotal',
				AverageCostAmount decimal(12,3) '@SaleItemAVGPrice',
				CouponNumber bigint '@SaleItemCouponNumber',
				CouponExpiration date '@CouponValidTo',
				DispenserNumber tinyint '@SaleItemPoint',
				NozzleNumber tinyint '@SaleItemPistol',

				ExciseTaxUnitExternalId varchar(8) '@ConsTaxUnitID',
				AgencySupplierNumber int '@SaleItemOwner',
				PromotionNumber int '@PromotionsID',
				FuelTemperature decimal(4,2) '@FuelTemperature',
				AlternativeVatCode varchar(2) '@AlternativeTaxCode',
				PurchasePrice decimal(9,3) '@SaleItemBuyPrice',
				NetAmountWithoutDiscount decimal(12,3) '@SaleItemNettoWithoutDiscount',
				GrossAmountWithoutDiscount decimal(12,3) '@SaleItemSumWithoutDiscount',
				PromotionDiscount decimal(12,3) '@DiscountPromo',
				BankCardDiscount decimal(12,3) '@DiscountBankCard',
				BankCardDiscountProfile int '@DiscountXProfBankCard',
				CarWashNumber int '@CarWashNumber',
				CarWashProgram int '@CarWashProgramNumber',
				CarWashTransactionId int '@CarWashTransId',
				CarWashAdditionalInfoTypeId int '@CarWashAddInfoType',
				CarWashAdditionalInfoValue nvarchar(2000) '@CarWashAddInfoValue',
				CustomerDiscount decimal(12,3) '@DiscountCust',
				CustomerDiscountProfile int '@DiscountXProfCust',
				CustomerCentralDiscount decimal(12,3) '@DiscountCustC',
				CustomerCentralDiscountProfile int '@DiscountXProfCustC',
				CustomerCentralDiscountCompensation decimal(12,3) '@DiscountCustCPart',
				VipDiscount decimal(12,3) '@DiscountVIP',
				VipDiscountProfile int '@DiscountXProfVIP',
				VipDiscountProfileName nvarchar(50) '@VIPDiscountXProfDescription',
				Nomenclature bigint '@ConsTaxCode',
				ExciseTaxRate decimal(10,4) '@ConsTaxRate',
				ExciseTaxAmount decimal(13,4) '@ConsTaxSum',
				CouponHash varchar(30) '@SaleItemCouponCode',
				ChargeType varchar(8) '@ChargeType',
				ChargeCardNumber varchar(50) '@ChargeCardPAN',
				ChargeApprovalCode varchar(20) '@ChargeApprovalCode',
				Charged datetime2(2) '@ChargeTimeStamp',
				PromoAuthorizationCode varchar(20) '@PromoAuthCode',
				PromoAuthorizationCodeType varchar(20) '@PromoAuthCodeType',
				IsCouponOptBound bit '@CouponUseInOPT',
				IsPriceEanScanned bit '@IsPriceEANScanned',
				IsTandem bit '@SetIdentifier',
				CouponSerialNumber varchar(30) '@SaleItemCouponSerialNum',
				IsOnline bit '@SaleItemOnlineStatus',

				IsVatExempt bit '@TaxIsVATFree',
				VatCode char(1) '@TaxLetter',
				IsRecipe bit '@SaleItemLineReceipt',
				GoodsExternalCode varchar(12) '@GoodsPKWCode',
				RecyclingFee decimal(12,3) '@RecyclingFeeAmount',
				FuelingStarted datetime2(0) '@FuellingStart',
				FuelingFinished datetime2(0) '@FuellingEnd',
				SupershopPointsGained int '@Points',
				SupershopPointsRequested int '@RequiredPoints',

				Closed datetime2(0) '../@SaleClose'
			) TAB
			CROSS APPLY (
				SELECT
					Sale.GetPaymentTypeGroupIDForSale('PT_COUP', NULL, TAB.CouponTypeExternalId, TAB.CouponExternalId) AS CouponPaymentTypeGroupID,
					UniCustomer.GetUniCustomerSettingsValue('Catman.Goods.Rounding', @UniCustomerID) AS RoundingGoodsNumber
			) E
			LEFT OUTER JOIN FuelSupply.FuelTank FT ON FT.PetrolStationID = @PetrolStationID
				AND FT.Number = TAB.FuelTankNumber
			LEFT OUTER JOIN Catman.Goods G ON G.UniCustomerID = @UniCustomerID
				AND G.Number = CASE WHEN TAB.GoodsNumber LIKE '01%' THEN @DoFoLocalArticleGoodsNumber ELSE TAB.GoodsNumber END
				AND (G.IsCentral = 1
					OR G.PetrolStationID = @PetrolStationID
				)
			LEFT OUTER JOIN FuelPricing.OperationMode OM ON OM.ExternalId = TAB.OperationModeExternalId
			LEFT OUTER JOIN Catman.Unit U ON U.ExternalId = TAB.ExciseTaxUnitExternalId
			LEFT OUTER JOIN (
				SELECT
					ID,
					PetrolStationID,
					UniCustomerID,
					Number
				FROM Supply.Supplier AGN1
				WHERE AGN1.IsCentral = 0
					AND AGN1.UniCustomerID = @UniCustomerID
				UNION
				SELECT
					AGN2.ID,
					AGN2.PetrolStationID,
					AGN2.UniCustomerID,
					AGN2.Number
				FROM Supply.Supplier AGN2
				WHERE AGN2.IsCentral = 1
			) AGN ON (AGN.PetrolStationID IS NULL
					OR AGN.PetrolStationID = @PetrolStationID
				)
				AND AGN.Number = TAB.AgencySupplierNumber
			LEFT OUTER JOIN Marketing.PromotionPetrolStationView PV ON PV.Number = TAB.PromotionNumber
				AND PV.PetrolStationID = @PetrolStationID
				AND PV.ValidFrom <= TAB.Closed
				AND PV.ValidTo >= TAB.Closed
			LEFT OUTER JOIN	Catman.CardTerminalGroup CTG ON CTG.UniCustomerID = @UniCustomerID
				AND CTG.Number = TAB.CardTermGroupNumber

		IF OBJECT_ID('tempdb..#LocalGoodsMapping') IS NOT NULL
			DROP TABLE #LocalGoodsMapping;

		CREATE TABLE #LocalGoodsMapping (
			RowNumber int,
			GoodsNumber varchar(9)
		)

		IF (@IsFranchise = 1)
		BEGIN
			INSERT INTO #LocalGoodsMapping
			SELECT
				ROW_NUMBER() OVER (ORDER BY LGM.GoodsNumber) Row,
				LGM.GoodsNumber
			FROM (
				SELECT DISTINCT TAB.GoodsNumber
				FROM OPENXML(@Handle, 'SALES/Sale/SaleItem')
					WITH (
						GoodsNumber varchar(9) '@GoodsID'
					) TAB
				WHERE TAB.GoodsNumber LIKE '01%'
			) LGM
		END

		INSERT INTO @LoyaltySale (
			SaleExternalId,
			LoyaltyCardID,
			LoyaltyCustomerID,
			CardNumber,
			IsOnline,
			IsVirtualCard,

			DBLoyaltyCardID,
			DBLoyaltyCustomerID
		)
		SELECT
			TAB.SaleExternalId,
			TAB.LoyaltyCardID,
			TAB.LoyaltyCustomerID,
			TAB.CardNumber,
			TAB.IsOnline,
			TAB.IsVirtualCard,

			CRD.ID,
			CUS.ID
		FROM OPENXML(@Handle, '/SALES/Sale/LMSTransaction')
			WITH (
				SaleExternalId int '../@SaleID',
				LoyaltyCardID int '@CardEvidenceNumber',
				LoyaltyCustomerID int '@CustomerNumber',
				CardNumber varchar(30) '@CardNumber',
				IsOnline bit '@IsOnline',
				IsVirtualCard bit '@IsVirtual',

				LoyaltyTransactionType varchar(20) '@LMSType',
				RequestId int '@LMSRequestID'
			) TAB
			LEFT OUTER JOIN Loyalty.LoyaltyCard CRD ON CRD.ID = TAB.LoyaltyCardID
				AND CRD.UniCustomerID = @UniCustomerID
			LEFT OUTER JOIN Loyalty.LoyaltyCustomer CUS ON CUS.ID = TAB.LoyaltyCustomerID
				AND CUS.UniCustomerID = @UniCustomerID

		INSERT INTO @LoyaltySaleItem (
			SaleExternalId,
			SaleItemOrder,
			AccrualProfileID,
			RedemptionDiscountTypeSecondaryExternalId,
			RedemptionProfileID,
			AccruedPoints,
			RedeemedPoints,
			Discount,
			CompensationAmount,

			DBAccrualProfileID,
			DBRedemptionDiscountTypeID,
			DBRedemptionProfileID
		)
		SELECT
			TAB.SaleExternalId,
			TAB.SaleItemOrder,
			TAB.AccrualProfileID,
			TAB.RedemptionDiscountTypeSecondaryExternalId,
			TAB.RedemptionProfileID,
			TAB.AccruedPoints,
			TAB.RedeemedPoints,
			TAB.Discount,
			TAB.CompensationAmount,

			AP.ID,
			DT.ID,
			RP.ID
		FROM OPENXML(@Handle, '/SALES/Sale/SaleItem/LMSItem')
			WITH (
				SaleExternalId int '../../@SaleID',
				SaleItemOrder smallint '../@SaleItemLine',
				AccrualProfileID int '@EarnProfileNumber',
				RedemptionDiscountTypeSecondaryExternalId tinyint '@DiscountSubtype',
				RedemptionProfileID int '@BurnProfileNumber',
				AccruedPoints decimal(13,4) '@LMSPointsEarned',
				RedeemedPoints decimal(13,4) '@LMSPointsBurned',
				Discount decimal(12,3) '@LMSDiscount',
				CompensationAmount decimal(12,3) '@LMSCompPrice'
			) TAB
			LEFT OUTER JOIN Loyalty.AccrualProfile AP ON AP.ID = TAB.AccrualProfileID
				AND AP.UniCustomerID = @UniCustomerID
			LEFT OUTER JOIN Loyalty.RedemptionDiscountType DT ON DT.SecondaryExternalId = TAB.RedemptionDiscountTypeSecondaryExternalId
			LEFT OUTER JOIN Loyalty.RedemptionProfile RP ON RP.ID = TAB.RedemptionProfileID
				AND RP.UniCustomerID = @UniCustomerID

		INSERT INTO @AccruedLoyaltyPoint (
			SaleExternalId,
			[Order],
			LoyaltyPointTypeID,
			PromotionNumber,
			CardNumber,
			Quantity,
			IsOnline,

			DBLoyaltyPointTypeID,
			DBPromotionID
		)
		SELECT
			TAB.SaleExternalId,
			ROW_NUMBER() OVER (PARTITION BY TAB.SaleExternalId ORDER BY TAB.LoyaltyPointTypeID),
			TAB.LoyaltyPointTypeID,
			TAB.PromotionNumber,
			TAB.CardNumber,
			TAB.Quantity,
			TAB.IsOnline,

			LPT.ID,
			PV.ID
		FROM OPENXML(@Handle, '/SALES/Sale/LoyaltyPoints')
			WITH (
				SaleExternalId int '../@SaleID',
				LoyaltyPointTypeID tinyint '@LoyaltyPointsType',
				PromotionNumber int '@PromotionID',
				CardNumber varchar(30) '@LoyaltyCardNumber',
				Quantity decimal(9,4) '@PointAmount',
				IsOnline bit '@IsOnline'
			) TAB
			LEFT OUTER JOIN Sale.LoyaltyPointType LPT ON LPT.ID = TAB.LoyaltyPointTypeID
			LEFT OUTER JOIN Marketing.PromotionPetrolStationView PV ON PV.Number = TAB.PromotionNumber
				AND PV.PetrolStationID = @PetrolStationID

		INSERT INTO @UnknownCode (
			SaleExternalId,
			[Order],
			Scanned,
			Code
		)
		SELECT
			TAB.SaleExternalId,
			ROW_NUMBER() OVER (PARTITION BY TAB.SaleExternalId ORDER BY TAB.Scanned),
			TAB.Scanned,
			TAB.Code
		FROM OPENXML(@Handle, '/SALES/Sale/UnknownEAN')
			WITH (
				SaleExternalId int '../@SaleID',
				Scanned datetime2(0) '@CodeScanningTime',
				Code varchar(200) '@Code'
			) TAB

		INSERT INTO @IssuedCoupon (
			SaleExternalId,
			CouponTypeExternalId,
			CouponExternalId,
			Number,
			Barcode,
			NominalValue,
			Expiration,
			SecondaryId,
			RuleNumber,

			DBCouponPaymentTypeGroupID
		)
		SELECT
			TAB.SaleExternalId,
			TAB.CouponTypeExternalId,
			TAB.CouponExternalId,
			TAB.Number,
			TAB.Barcode,
			TAB.NominalValue,
			TAB.Expiration,
			TAB.SecondaryId,
			TAB.RuleNumber,

			PT.CouponPaymentTypeGroupID
		FROM OPENXML(@Handle, '/SALES/Sale/IssuedCoupon')
			WITH (
				SaleExternalId int '../@SaleID',
				CouponTypeExternalId varchar(12) '@CouponTypeID',
				CouponExternalId varchar(15) '@CouponID',
				Number int '@CouponNumber',
				Barcode varchar(14) '@CouponEAN',
				NominalValue decimal(9,3) '@CouponNominalValue',
				Expiration date '@CouponValidTo',
				SecondaryId varchar(30) '@CouponSecID',
				RuleNumber int '@IssueRuleNumber',

				CouponIsCentral bit '@CouponIsCentral'
			) TAB
			CROSS APPLY (
				SELECT Sale.GetPaymentTypeGroupIDForSale('PT_COUP', NULL, TAB.CouponTypeExternalId, TAB.CouponExternalId) AS CouponPaymentTypeGroupID
			) PT

		INSERT INTO @AppliedPromotion (
			SaleExternalId,
			PromotionNumber,
			Promotions,

			DBPromotionID
		)
		SELECT
			TAB.SaleExternalId,
			TAB.PromotionNumber,
			TAB.Promotions,

			PV.ID
		FROM OPENXML(@Handle, '/SALES/Sale/PromotionsCounter')
			WITH (
				SaleExternalId int '../@SaleID',
				PromotionNumber int '@PromotionsID',
				Promotions smallint '@UseCount'
			) TAB
			LEFT OUTER JOIN Marketing.PromotionPetrolStationView PV ON PV.Number = TAB.PromotionNumber
				AND PV.PetrolStationID = @PetrolStationID

		INSERT INTO @ReturnedCash (
			SaleExternalId,
			ClientAppCurrencyID,
			ExchangeRate,
			Amount,
			IsTerminalCashback,

			DBCurrencyID
		)
		SELECT
			TAB.SaleExternalId,
			TAB.ClientAppCurrencyID,
			TAB.ExchangeRate,
			TAB.Amount,
			TAB.IsTerminalCashback,

			CUR.CurrencyID
		FROM OPENXML(@Handle, '/SALES/Sale/ReturnedCash')
			WITH (
				SaleExternalId int '../@SaleID',
				ClientAppCurrencyID char(3) '@ReturnedCurrencyID',
				ExchangeRate decimal(12,6) '@ReturnedCurrRation',
				Amount decimal(13,4) '@ReturnedCashSum',
				IsTerminalCashback bit '@IsTerminalCashback'
			) TAB
			LEFT OUTER JOIN PetrolStationTransfer.ImportDialogCurrency CUR ON CUR.ID = TAB.ClientAppCurrencyID

		INSERT INTO @AccruedSupershopPoint (
			CardNumber,
			TransactionId,
			TransactionNumber,
			TerminalId,
			PosId,
			TotalPoints,
			PointsGained,
			PointsRate,
			ResponseMessage
		)
		SELECT
			TAB.CardNumber,
			TAB.TransactionId,
			TAB.TransactionNumber,
			TAB.TerminalId,
			TAB.PosId,
			TAB.TotalPoints,
			TAB.PointsGained,
			TAB.PointsRate,
			TAB.ResponseMessage
		FROM OPENXML(@Handle, '/SALES/Sale/EarnPoints')
			WITH (
				CardNumber varchar(80) '@CardPan',
				TransactionId varchar(50) '@TrxId',
				TransactionNumber varchar(50) '@TranId',
				TerminalId int '@SAMId',
				PosId varchar(50) '@PosId',
				TotalPoints int '@Balance',
				PointsGained int '@Points',
				PointsRate int '@Rate',
				ResponseMessage nvarchar(120) '@ResponseMessage'
			) TAB

		INSERT INTO @FiscalRegistration (
			NodeId,
			SaleExternalId,
			[Order],
			BusinessPremisesId,
			ReceiptNumber,
			ExportedReceiptNumber,
			TaxpayerTaxNumber,
			AppointingTaxpayerTaxNumber,
			GrossAmount,
			NetAmountExemptFromVat,
			NetAmountBasicVatRate,
			NetAmountReducedVatRate,
			NetAmountSecondReducedVatRate,
			VatAmountBasicVatRate,
			VatAmountReducedVatRate,
			VatAmountSecondReducedVatRate,
			IntendedSubsequentDrawingGrossAmount,
			SubsequentDrawingGrossAmount,
			FiscalIdentificationCode,
			TaxpayerSecurityCode,
			TaxpayerSignatureCode,
			RequestStatus,
			RequestErrorCode,
			RequestErrorMessage
		)
		SELECT
			TAB.NodeId,
			TAB.SaleExternalId,
			ROW_NUMBER() OVER (PARTITION BY TAB.SaleExternalId ORDER BY TAB.NodeId),
			TAB.BusinessPremisesId,
			TAB.ReceiptNumber,
			TAB.ExportedReceiptNumber,
			TAB.TaxpayerTaxNumber,
			NULLIF(TAB.AppointingTaxpayerTaxNumber, ''),
			TAB.GrossAmount,
			TAB.NetAmountExemptFromVat,
			TAB.NetAmountBasicVatRate,
			TAB.NetAmountReducedVatRate,
			TAB.NetAmountSecondReducedVatRate,
			TAB.VatAmountBasicVatRate,
			TAB.VatAmountReducedVatRate,
			TAB.VatAmountSecondReducedVatRate,
			TAB.IntendedSubsequentDrawingGrossAmount,
			TAB.SubsequentDrawingGrossAmount,
			NULLIF(TAB.FiscalIdentificationCode, ''),
			TAB.TaxpayerSecurityCode,
			TAB.TaxpayerSignatureCode,
			TAB.RequestStatus,
			TAB.RequestErrorCode,
			TAB.RequestErrorMessage
		FROM OPENXML(@Handle, '/SALES/Sale/EETInformation')
			WITH (
				NodeId bigint '@mp:id',
				SaleExternalId int '../@SaleID',
				BusinessPremisesId int '@BusinessPremiseID',
				ReceiptNumber varchar(30) '@ReceiptNumberES',
				ExportedReceiptNumber varchar(30) '@ReceiptNumberEET',
				TaxpayerTaxNumber varchar(20) '@TAXNumber',
				AppointingTaxpayerTaxNumber varchar(20) '@MandatingTAXNumber',
				GrossAmount decimal(12,3) '@TotalAmount',
				NetAmountExemptFromVat decimal(12,3) '@ExemptTransactions',
				NetAmountBasicVatRate decimal(12,3) '@TaxBase1',
				NetAmountReducedVatRate decimal(12,3) '@TaxBase2',
				NetAmountSecondReducedVatRate decimal(12,3) '@TaxBase3',
				VatAmountBasicVatRate decimal(12,3) '@Tax1',
				VatAmountReducedVatRate decimal(12,3) '@Tax2',
				VatAmountSecondReducedVatRate decimal(12,3) '@Tax3',
				IntendedSubsequentDrawingGrossAmount decimal(12,3) '@SUAmount',
				SubsequentDrawingGrossAmount decimal(12,3) '@SAmount',
				FiscalIdentificationCode varchar(100) '@FIK',
				TaxpayerSecurityCode varchar(44) '@BKP',
				TaxpayerSignatureCode varchar(344) '@PKP',
				RequestStatus tinyint '@RequestStatus',
				RequestErrorCode varchar(10) '@ErrorCode',
				RequestErrorMessage nvarchar(150) '@ErrorMessage',
				ReceiptModificationTypeExternalId tinyint '../@ChangeDoc'
			) TAB
			INNER JOIN Sale.ReceiptModificationType MT ON MT.ExternalId = TAB.ReceiptModificationTypeExternalId
		WHERE MT.IsUpdateEnabled = 0

		INSERT INTO @FiscalRegistrationWarning (
			FiscalRegistrationNodeId,
			Code,
			Message
		)
		SELECT
			TAB.FiscalRegistrationNodeId,
			TAB.Code,
			TAB.Message
		FROM OPENXML(@Handle, '/SALES/Sale/EETInformation/EETWarning')
			WITH (
				FiscalRegistrationNodeId bigint '@mp:parentid',
				Code varchar(10) '@Code',
				Message nvarchar(150) '@Message'
			) TAB

		INSERT INTO @DeletedSaleItem (
			PetrolStationID,
			GoodsNumber,
			ShiftNumber,
			ShiftDate,
			ExternalId,
			Deleted,
			PosNumber,
			EanCode,
			Quantity,
			GrossPrice,
			GrossAmount,
			VatRate,
			AlternativeVatCode,

			DBGoodsID
		)
		SELECT
			@PetrolStationID,
			CASE WHEN TAB.GoodsNumber LIKE '01%' THEN @DoFoLocalArticleGoodsNumber ELSE TAB.GoodsNumber END,
			TAB.ShiftNumber,
			TAB.ShiftDate,
			TAB.ExternalId,
			TAB.Deleted,
			TAB.PosNumber,
			TAB.EanCode,
			TAB.Quantity,
			TAB.GrossPrice,
			TAB.GrossAmount,
			TAB.VatRate,
			TAB.AlternativeVatCode,

			G.ID
		FROM OPENXML(@Handle, '/SALES/DeletedSaleLine')
			WITH (
				GoodsNumber varchar(9) '@GoodsID',
				ShiftNumber smallint '@ShiftNumber',
				ShiftDate date '@ShiftDate',
				ExternalId int '@DeletedSaleLineID',
				Deleted datetime2(0) '@Time',
				PosNumber tinyint '@POSNumber',
				EanCode varchar(14) '@EAN',
				Quantity decimal(10,4) '@DeletedQuant',
				GrossPrice decimal(9,3) '@UnitPrice',
				GrossAmount decimal(12,3) '@SumPrice',
				VatRate decimal(5,2) '@TaxRate',
				AlternativeVatCode varchar(2) '@AlternativeTaxCode',

				IsVatExempt bit '@TaxIsVATFree',
				VatCode char(1) '@TaxLetter'
			) TAB
			LEFT OUTER JOIN Catman.Goods G ON G.UniCustomerID = @UniCustomerID
				AND G.Number = CASE WHEN TAB.GoodsNumber LIKE '01%' THEN @DoFoLocalArticleGoodsNumber ELSE TAB.GoodsNumber END
				AND (G.IsCentral = 1
					OR G.PetrolStationID = @PetrolStationID
				)

		INSERT INTO @CashMovement (
			PetrolStationID,
			CardTypeExternalId,
			CashMovementTypeExternalId,
			CashMovementTypeExternalSign,
			ClientAppCurrencyID,
			ShiftNumber,
			ShiftDate,
			ExternalId,
			Entered,
			Number,
			PosNumber,
			PosUserNumber,
			NetAmount,
			GrossAmount,
			VatRate,
			AlternativeVatCode,
			ExchangeRate,
			CardExtendedInfo,
			Note,
			IsCancel,
			IsCashAffected,
			IsSaldoAffected,
			IsTurnoverAffected,

			DBCardPaymentTypeGroupID,
			DBCashMovementTypeID,
			DBCurrencyID
		)
		SELECT
			@PetrolStationID,
			TAB.CardTypeExternalId,
			TAB.CashMovementTypeExternalId,
			TAB.CashMovementTypeExternalSign,
			TAB.ClientAppCurrencyID,
			TAB.ShiftNumber,
			TAB.ShiftDate,
			TAB.ExternalId,
			TAB.Entered,
			TAB.Number,
			TAB.PosNumber,
			TAB.PosUserNumber,
			TAB.NetAmount,
			TAB.GrossAmount,
			TAB.VatRate,
			TAB.AlternativeVatCode,
			TAB.ExchangeRate,
			TAB.CardExtendedInfo,
			TAB.Note,
			TAB.IsCancel,
			TAB.IsCashAffected,
			TAB.IsSaldoAffected,
			TAB.IsTurnoverAffected,

			PT.CardPaymentTypeGroupID,
			CMT.ID,
			CUR.CurrencyID
		FROM OPENXML(@Handle, '/SALES/CashMove')
			WITH (
				CashMovementTypeExternalId tinyint '@CashMoveTypeNumber',
				CashMovementTypeExternalSign smallint '@CashMoveTypeSign',
				ClientAppCurrencyID char(3) '@CurrencyID',
				CardTypeExternalId varchar(8) '@CashMoveCardTypeID',
				ShiftNumber smallint '@ShiftNumber',
				ShiftDate date '@ShiftDate',
				ExternalId int '@CashMoveID',
				Entered datetime2(0) '@CashMoveDate',
				Number int '@CashMoveNumber',
				PosNumber tinyint '@CashMovePosNumber',
				PosUserNumber smallint '@CashMoveUser',
				NetAmount decimal(12,3) '@CashMoveSumNetto',
				GrossAmount decimal(12,3) '@CashMoveSum',
				VatRate decimal(5,2) '@CashMoveTax',
				AlternativeVatCode varchar(2) '@AlternativeTaxCode',
				ExchangeRate decimal(12,6) '@CashMoveCurrRation',
				CardExtendedInfo varchar(50) '@CashMoveCardNote',
				Note nvarchar(50) '@CashMoveNote',
				IsCancel bit '@CashMoveCanceled',
				IsCashAffected bit '@CashMoveAffectCash',
				IsSaldoAffected bit '@CashMoveAffectSaldo',
				IsTurnoverAffected bit '@CashMoveAffectTurnOver',

				CashMovementTypeName nvarchar(50) '@CashMoveTypeName',
				IsVatExempt bit '@TaxIsVATFree',
				VatCode char(1) '@TaxLetter',
				CashMovementTypeExternalSysId int '@CashMoveTypeID'
			) TAB
			CROSS APPLY (
				SELECT Sale.GetPaymentTypeGroupIDForSale('PT_BANC', TAB.CardTypeExternalId, NULL, NULL) AS CardPaymentTypeGroupID
			) PT
			LEFT OUTER JOIN Sale.CashMovementType CMT ON CMT.ExternalId = TAB.CashMovementTypeExternalId
				AND CMT.ExternalSign = TAB.CashMovementTypeExternalSign
			LEFT OUTER JOIN PetrolStationTransfer.ImportDialogCurrency CUR ON CUR.ID = TAB.ClientAppCurrencyID

		INSERT INTO @CashMovementCoupon (
			CashMovementExternalId,
			[Order],
			CouponPaymentTypeGroupID,
			Number,
			Hash,
			GrossAmount
		)
		SELECT
			TAB.CashMovementExternalId,
			ROW_NUMBER() OVER (PARTITION BY TAB.CashMovementExternalId ORDER BY TAB.Number),
			PT.CouponPaymentTypeGroupID,
			TAB.Number,
			TAB.Hash,
			TAB.GrossAmount
		FROM OPENXML(@Handle, '/SALES/CashMove/OPTCoupons')
			WITH (
				CashMovementExternalId int '../@CashMoveID',
				Number bigint '@CpnNumber',
				Hash varchar(30) '@CpnCode',
				GrossAmount decimal(12,3) '@CpnValue'
			) TAB
			CROSS APPLY (
				SELECT Sale.GetPaymentTypeGroupIDForSale('PT_COUP', NULL, 'CPNT_OPT', 'CPN_OPT') AS CouponPaymentTypeGroupID
			) PT

		INSERT INTO @FiscalRegistration (
			NodeId,
			CashMovementExternalId,
			[Order],
			BusinessPremisesId,
			ReceiptNumber,
			ExportedReceiptNumber,
			TaxpayerTaxNumber,
			AppointingTaxpayerTaxNumber,
			GrossAmount,
			NetAmountExemptFromVat,
			NetAmountBasicVatRate,
			NetAmountReducedVatRate,
			NetAmountSecondReducedVatRate,
			VatAmountBasicVatRate,
			VatAmountReducedVatRate,
			VatAmountSecondReducedVatRate,
			IntendedSubsequentDrawingGrossAmount,
			SubsequentDrawingGrossAmount,
			FiscalIdentificationCode,
			TaxpayerSecurityCode,
			TaxpayerSignatureCode,
			RequestStatus,
			RequestErrorCode,
			RequestErrorMessage
		)
		SELECT
			TAB.NodeId,
			TAB.CashMovementExternalId,
			ROW_NUMBER() OVER (PARTITION BY TAB.CashMovementExternalId ORDER BY TAB.NodeId),
			TAB.BusinessPremisesId,
			TAB.ReceiptNumber,
			TAB.ExportedReceiptNumber,
			TAB.TaxpayerTaxNumber,
			NULLIF(TAB.AppointingTaxpayerTaxNumber, ''),
			TAB.GrossAmount,
			TAB.NetAmountExemptFromVat,
			TAB.NetAmountBasicVatRate,
			TAB.NetAmountReducedVatRate,
			TAB.NetAmountSecondReducedVatRate,
			TAB.VatAmountBasicVatRate,
			TAB.VatAmountReducedVatRate,
			TAB.VatAmountSecondReducedVatRate,
			TAB.IntendedSubsequentDrawingGrossAmount,
			TAB.SubsequentDrawingGrossAmount,
			NULLIF(TAB.FiscalIdentificationCode, ''),
			TAB.TaxpayerSecurityCode,
			TAB.TaxpayerSignatureCode,
			TAB.RequestStatus,
			TAB.RequestErrorCode,
			TAB.RequestErrorMessage
		FROM OPENXML(@Handle, '/SALES/CashMove/EETInformation')
			WITH (
				NodeId bigint '@mp:id',
				CashMovementExternalId int '../@CashMoveID',
				BusinessPremisesId int '@BusinessPremiseID',
				ReceiptNumber varchar(30) '@ReceiptNumberES',
				ExportedReceiptNumber varchar(30) '@ReceiptNumberEET',
				TaxpayerTaxNumber varchar(20) '@TAXNumber',
				AppointingTaxpayerTaxNumber varchar(20) '@MandatingTAXNumber',
				GrossAmount decimal(12,3) '@TotalAmount',
				NetAmountExemptFromVat decimal(12,3) '@ExemptTransactions',
				NetAmountBasicVatRate decimal(12,3) '@TaxBase1',
				NetAmountReducedVatRate decimal(12,3) '@TaxBase2',
				NetAmountSecondReducedVatRate decimal(12,3) '@TaxBase3',
				VatAmountBasicVatRate decimal(12,3) '@Tax1',
				VatAmountReducedVatRate decimal(12,3) '@Tax2',
				VatAmountSecondReducedVatRate decimal(12,3) '@Tax3',
				IntendedSubsequentDrawingGrossAmount decimal(12,3) '@SUAmount',
				SubsequentDrawingGrossAmount decimal(12,3) '@SAmount',
				FiscalIdentificationCode varchar(100) '@FIK',
				TaxpayerSecurityCode varchar(44) '@BKP',
				TaxpayerSignatureCode varchar(344) '@PKP',
				RequestStatus tinyint '@RequestStatus',
				RequestErrorCode varchar(10) '@ErrorCode',
				RequestErrorMessage nvarchar(150) '@ErrorMessage'
			) TAB

		INSERT INTO @FiscalRegistrationWarning (
			FiscalRegistrationNodeId,
			Code,
			Message
		)
		SELECT
			TAB.FiscalRegistrationNodeId,
			TAB.Code,
			TAB.Message
		FROM OPENXML(@Handle, '/SALES/CashMove/EETInformation/EETWarning')
			WITH (
				FiscalRegistrationNodeId bigint '@mp:parentid',
				Code varchar(10) '@Code',
				Message nvarchar(150) '@Message'
			) TAB

		INSERT INTO @RecipeComponent (
			SaleExternalId,
			SaleItemOrder,
			AgencySupplierNumber,
			GoodsNumber,
			AverageCostAmount,
			Quantity,

			DBAgencySupplierID,
			DBGoodsID
		)
		SELECT
			TAB.SaleExternalId,
			TAB.SaleItemOrder,
			TAB.AgencySupplierNumber,
			TAB.GoodsNumber,
			TAB.AverageCostAmount,
			TAB.Quantity,

			AGS.ID,
			G.ID
		FROM OPENXML(@Handle, '/SALES/Sale/SaleItem/RecipeComponent')
			WITH (
				SaleExternalId int '../../@SaleID',
				SaleItemOrder smallint '../@SaleItemLine',
				GoodsNumber varchar(9) '@GoodsID',
				Quantity decimal(10, 4) '@Quantity',
				AverageCostAmount decimal(13, 4) '@AVGPrice',
				AgencySupplierNumber int '@OwnerID'
			) TAB
			LEFT OUTER JOIN Catman.Goods G ON G.UniCustomerID = @UniCustomerID
				AND G.Number = TAB.GoodsNumber
				AND (G.IsCentral = 1
					OR G.PetrolStationID = @PetrolStationID
				)
			LEFT OUTER JOIN (
				SELECT
					ID,
					PetrolStationID,
					UniCustomerID,
					Number
				FROM Supply.Supplier
				WHERE IsCentral = 0
					AND UniCustomerID = @UniCustomerID
				UNION
				SELECT
					ID,
					PetrolStationID,
					UniCustomerID,
					Number
				FROM Supply.Supplier
				WHERE IsCentral = 1
			) AGS ON (AGS.PetrolStationID IS NULL
					OR AGS.PetrolStationID = @PetrolStationID
				)
				AND AGS.Number = TAB.AgencySupplierNumber
-- zatim ignorovat do vyreseni rizeni MT z WO
/*
		INSERT INTO @MarketingText (
			SaleExternalId,
			MarketingTextID,
			CodeType,
			CodeValue
		)
		SELECT
			TAB.SaleExternalId,
			TAB.MarketingTextID,
			TAB.CodeType,
			TAB.CodeValue
		FROM OPENXML(@Handle, '/SALES/Sale/MarketingText')
			WITH (
				SaleExternalId int '../@SaleID',
				MarketingTextID int '@MarketingTextID',
				CodeType tinyint '@CodeType',
				CodeValue varchar(20) '@CodeValue'
			) TAB
*/
		INSERT INTO @CustomerUpdate (
			SaleExternalId,
			SaleNumber,
			PosNumber,
			SaleClosed,
			CustomerName,
			CustomerNumber,
			CustomerTaxID,
			CustomerAddress,
			CustomerCity,
			CustomerCountry,
			CustomerZip
		)
		SELECT
			TAB.SaleExternalId,
			TAB.SaleNumber,
			TAB.PosNumber,
			TAB.SaleClosed,
			TAB.CustomerName,
			TAB.CustomerNumber,
			TAB.CustomerTaxID,
			TAB.CustomerAddress,
			TAB.CustomerCity,
			TAB.CustomerCountry,
			TAB.CustomerZip
		FROM OPENXML(@Handle, '/SALES/CustomerUpdate')
			WITH (
				SaleExternalId int '@SaleID',
				SaleNumber smallint '@SaleNumber',
				PosNumber tinyint '@SalePosNumber',
				SaleClosed datetime2(3) '@SaleClose',
				CustomerName varchar(100) '@SaleCustName',
				CustomerNumber varchar(20) '@SaleCustID',
				CustomerTaxID varchar(20) '@SaleCustTaxID',
				CustomerAddress varchar(100) '@SaleCustAddress',
				CustomerCity varchar(60) '@SaleCustCity',
				CustomerCountry varchar(30) '@SaleCustCountry',
				CustomerZip varchar(10) '@SaleCustZIP'
			) TAB

		INSERT INTO @FiscalRegistrationUpdate (
			SaleExternalId,
			BusinessPremiseNumber,
			SaleNumber,
			PosNumber,
			SaleClosed,
			RequestStatus,
			ReceiptNumberEs,
			ReceiptNumberEet,
			TaxNumber,
			MandatingTaxNumber,
			FiscalIdentificationCode,
			TaxpayerSecurityCode,
			TaxpayerSignatureCode,
			ErrorCode,
			ErrorMessage
		)
		SELECT
			TAB.SaleExternalId,
			TAB.BusinessPremiseNumber,
			TAB.SaleNumber,
			TAB.PosNumber,
			TAB.SaleClosed,
			TAB.RequestStatus,
			TAB.ReceiptNumberEs,
			TAB.ReceiptNumberEet,
			TAB.TaxNumber,
			TAB.MandatingTaxNumber,
			TAB.FiscalIdentificationCode,
			TAB.TaxpayerSecurityCode,
			TAB.TaxpayerSignatureCode,
			TAB.ErrorCode,
			TAB.ErrorMessage
		FROM OPENXML(@Handle, '/SALES/EETUpdate')
			WITH (
				SaleExternalId int '@SaleID',
				BusinessPremiseNumber int '@BusinessPremiseID',
				SaleNumber smallint '@SaleNumber',
				PosNumber tinyint '@SalePosNumber',
				SaleClosed datetime2(3) '@SaleClose',
				RequestStatus tinyint '@RequestStatus',
				ReceiptNumberEs varchar(30) '@ReceiptNumberES',
				ReceiptNumberEet varchar(30) '@ReceiptNumberEET',
				TaxNumber varchar(20) '@TAXNumber',
				MandatingTaxNumber varchar(20) '@MandatingTAXNumber',
				FiscalIdentificationCode varchar(100) '@FIK',
				TaxpayerSecurityCode varchar(44) '@BKP',
				TaxpayerSignatureCode varchar(344) '@PKP',
				ErrorCode varchar(10) '@ErrorCode',
				ErrorMessage varchar(150) '@ErrorMessage'
		) TAB

		INSERT INTO @OptReconciliation (
			PetrolStationID,
			UniCustomerID,
			ExternalId,
			TerminalId,
			TerminalTypeId,
			PosNumber,
			Batch,
			Amount,
			StatusNumber,
			StatusDescription,
			CloseDate,
			OpenDate,
			[User]
		)
		SELECT
			@PetrolStationID,
			@UniCustomerID,
			TAB.ExternalId,
			TAB.TerminalId,
			TAB.TerminalTypeId,
			TAB.PosNumber,
			TAB.Batch,
			TAB.Amount,
			TAB.StatusNumber,
			TAB.StatusDescription,
			TAB.CloseDate,
			TAB.OpenDate,
			TAB.[User]
		FROM OPENXML(@Handle, '/SALES/Reconciliation')
			WITH (
				ExternalId int '@LocalId',
				TerminalId varchar(20) '@TerminalId',
				TerminalTypeId varchar(10) '@TerminalType',
				PosNumber tinyint '@POSNumber',
				Batch int '@TerminalBatch',
				Amount decimal(12, 3) '@Sum',
				StatusNumber tinyint '@Status',
				StatusDescription nvarchar(40) '@StatusText',
				CloseDate datetime2(3) '@CloseDate',
				OpenDate datetime2(3) '@OpenDate',
				[User] nvarchar(20) '@User'
		) TAB

		INSERT INTO @OptBanknote (
			PetrolStationID,
			ExternalId,
			TerminalId,
			TerminalTypeId,
			PosNumber,
			CurrencyID,
			NominalValue,
			[Count],
			Amount,
			DamagedCount
		)
		SELECT
			@PetrolStationID,
			TAB.ExternalId,
			TAB.TerminalId,
			TAB.TerminalTypeId,
			TAB.PosNumber,
			TAB.CurrencyID,
			TAB.NominalValue,
			TAB.[Count],
			TAB.Amount,
			TAB.DamagedCount
		FROM OPENXML(@Handle, '/SALES/Reconciliation/Banknote')
			WITH (
				ExternalId int '../@LocalId',
				TerminalId varchar(20) '../@TerminalId',
				TerminalTypeId varchar(10) '../@TerminalType',
				PosNumber tinyint '../@POSNumber',
				CurrencyID char(3) '@CurrencyID',
				NominalValue int '@Nominal',
				[Count] int '@Count',
				Amount int '@Sum',
				DamagedCount int '@InsecureCount'
		) TAB

		EXEC sp_xml_removedocument @Handle

		SET @Handle = NULL

		SET @PetrolStationTypeID = (SELECT PetrolStationTypeID FROM PetrolStation.PetrolStation WHERE ID = @PetrolStationID)

		-- Validace --
		SET @ValidationMessage = ''

		SET @SaleRejectLowerLimit = Security.GetSettingsValue('PetrolStationTransfer.Import.Sale.RejectLowerLimit')
		SET @SaleRejectUpperLimit = Security.GetSettingsValue('PetrolStationTransfer.Import.Sale.RejectUpperLimit')

		SET @ClosedLowerLimit = DATEADD(MONTH, -@SaleRejectLowerLimit, Common.GetDateTime3())
		SET @ClosedUpperLimit = DATEADD(DAY, @SaleRejectUpperLimit, Common.GetDateTime3())

		SELECT @ValidationMessage +=
			CASE
				WHEN (Closed < @ClosedLowerLimit)
					THEN 'Sale ' + CAST(ExternalId AS nvarchar) + ' is older than ' + CAST(@SaleRejectLowerLimit AS nvarchar) + ' month' + IIF(@SaleRejectLowerLimit > 1, 's', '') + '. Import is not allowed.'
				WHEN (Closed > @ClosedUpperLimit)
					THEN 'Sale ' + CAST(ExternalId AS nvarchar) + ' is in the future more than ' + CAST(@SaleRejectUpperLimit AS nvarchar) + ' day' + IIF(@SaleRejectUpperLimit > 1, 's', '') + '. Import is not allowed.'
			END
			+ Common.GetEndLine()
		FROM #Sale
		WHERE IsUpdateEnabled = 0
			AND (Closed < @ClosedLowerLimit
				OR Closed > @ClosedUpperLimit
			)
		GROUP BY
			ExternalId,
			Closed

		IF (@ValidationMessage <> '')
		BEGIN
			RAISERROR(@ValidationMessage, 16, 1)
		END

		SELECT @ValidationMessage += 'Sale ' + CAST(TAB.ExternalId AS nvarchar) + ' already exists in the database. Import is not allowed.' + Common.GetEndLine()
		FROM #Sale TAB
			INNER JOIN Sale.Sale S ON S.PetrolStationID = TAB.PetrolStationID
				AND S.ExternalId = TAB.ExternalId
		WHERE TAB.IsUpdateEnabled = 0
		GROUP BY TAB.ExternalId

		SELECT @ValidationMessage += 'Sale ' + CAST(TAB.ExternalId AS nvarchar) + ' - there already exists a sale with identical SaleNumber, SaleClose, SalePosNumber and SaleSum.'
			+ ' It is saved in DB as Sale ' + CAST(S.ExternalId AS nvarchar) + '.' + Common.GetEndLine()
		FROM #Sale TAB
			INNER JOIN Sale.Sale S ON S.PetrolStationID = TAB.PetrolStationID
				AND S.ClosedDate = CAST(TAB.Closed AS date)
				AND S.PaymentOrder = TAB.PaymentOrder
				AND S.Number = TAB.Number
				AND S.Closed = TAB.Closed
				AND S.PosNumber = TAB.PosNumber
				AND S.ReceiptGrossAmount = TAB.ReceiptGrossAmount
				AND S.ExternalId <> TAB.ExternalId
		WHERE TAB.IsUpdateEnabled = 0
		GROUP BY
			TAB.ExternalId,
			S.ExternalId

		INSERT INTO @UpdatedSaleIDs (
			ID,
			PaymentOrder,
			ExternalId,
			ReceiptModificationTypeID,
			ReceiptTypeID,
			CustomerCity,
			CustomerCountry,
			CustomerIdentificationNumber,
			CustomerName,
			CustomerStreet,
			CustomerTaxNumber,
			CustomerZip,
			GreenCustomerNumber
		)
		SELECT
			S.ID,
			S.PaymentOrder,
			TAB.ExternalId,
			TAB.DBReceiptModificationTypeID,
			TAB.DBReceiptTypeID,
			TAB.CustomerCity,
			TAB.CustomerCountry,
			TAB.CustomerIdentificationNumber,
			TAB.CustomerName,
			TAB.CustomerStreet,
			TAB.CustomerTaxNumber,
			TAB.CustomerZip,
			TAB.GreenCustomerNumber
		FROM #Sale TAB
			LEFT OUTER JOIN Sale.Sale S ON S.PetrolStationID = TAB.PetrolStationID
				AND S.ExternalId = TAB.ExternalId
				AND S.PaymentOrder = TAB.PaymentOrder
		WHERE TAB.IsUpdateEnabled = 1

		SELECT @ValidationMessage += 'Sale ' + CAST(ExternalId AS nvarchar) + ' not found. Receipt cannot be modified.' + Common.GetEndLine()
		FROM @UpdatedSaleIDs
		WHERE ID IS NULL
		GROUP BY ExternalId

		SELECT @ValidationMessage += 'Sale ' + CAST(ExternalId AS nvarchar) + ' - the sum of PaymentPart attributes is not equal to 1.' + Common.GetEndLine()
		FROM #Sale
		WHERE IsUpdateEnabled = 0
		GROUP BY ExternalId
		HAVING ROUND(SUM(PaymentPart), 1) <> 1.0

		SELECT @ValidationMessage += 'Deleted item ' + CAST(TAB.ExternalId AS nvarchar) + ' already exists in the database. Import is not allowed.' + Common.GetEndLine()
		FROM @DeletedSaleItem TAB
			INNER JOIN Sale.DeletedSaleItem DSL ON DSL.PetrolStationID = TAB.PetrolStationID
				AND DSL.ExternalId = TAB.ExternalId

		SELECT @ValidationMessage += 'Cash movement ' + CAST(TAB.ExternalId AS nvarchar) + ' already exists in the database. Import is not allowed.' + Common.GetEndLine()
		FROM @CashMovement TAB
			INNER JOIN Sale.CashMovement CM ON CM.PetrolStationID = TAB.PetrolStationID
				AND CM.ExternalId = TAB.ExternalId

		IF (@ValidationMessage <> '')
		BEGIN
			RAISERROR(@ValidationMessage, 16, 1)
		END

		SELECT @ValidationMessage += 'Shift ' + CAST(SH.Number AS nvarchar) + ' from ' + CAST(SH.Date AS nvarchar) + ' -'
			+ DataProcessing.GetErrorIfValueNotExists(SHC.DBCurrencyID, 1, 'CurrencyID', SHC.ClientAppCurrencyID, ' ')
			+ Common.GetEndLine()
		FROM @ShiftCash SHC
			INNER JOIN @Shift SH ON SH.NodeId = SHC.ShiftNodeId
		WHERE SHC.DBCurrencyID IS NULL

		SELECT @ValidationMessage += 'Sale ' + CAST(ExternalId AS nvarchar) + ' -'
			+ DataProcessing.GetErrorIfValueNotExists(DBReceiptModificationTypeID, 1, 'ChangeDoc', ReceiptModificationTypeExternalId, ' ')
			+ DataProcessing.GetErrorIfValueNotExists(DBReceiptTypeID, 1, 'SaleSlipType', ReceiptTypeExternalId, ' ')
			+ Common.GetEndLine()
		FROM #Sale
		WHERE DBReceiptModificationTypeID IS NULL
			OR DBReceiptTypeID IS NULL
		GROUP BY
			ExternalId,
			DBReceiptModificationTypeID,
			ReceiptModificationTypeExternalId,
			DBReceiptTypeID,
			ReceiptTypeExternalId

		SELECT @ValidationMessage += 'Payment ' + CAST(PaymentOrder AS nvarchar) + ' within sale ' + CAST(ExternalId AS nvarchar) + ' -'
			+ DataProcessing.GetErrorIfValueNotExists(DBAdditionalCardID, 0, 'SupplementalCardEvidenceNumber', AdditionalCardExternalNumber, ' ')
			+ DataProcessing.GetErrorIfValueNotExists(DBAuthorizationTypeID, 0, 'PaymentTransOnline', AuthorizationTypeExternalId, ' ')
			+ DataProcessing.GetErrorIfValueNotExists(DBBonusCardID, 0, 'BonusCardEvidenceNumber', BonusCardExternalNumber, ' ')
			+ DataProcessing.GetErrorIfValueNotExists(DBBonusPaymentTypeGroupID, 0, 'BonusCardTypeID', BonusCardTypeExternalId, ' ')
			+ DataProcessing.GetErrorIfValueNotExists(DBCurrencyID, 1, 'CurrencyID', ClientAppCurrencyID, ' ')
			+ DataProcessing.GetErrorIfValueNotExists(DBInvoiceCardID, 0, 'InvoiceCardEvidenceNumber', InvoiceCardExternalNumber, ' ')
			+ CASE WHEN (DBPaymentTypeGroupID IS NULL)
				THEN ' Combination of attributes '
					+ 'PaymentTypeID "' + PaymentTypeExternalId + '", '
					+ 'CardTypeID "' + ISNULL(CardTypeExternalId, 'NULL') + '", '
					+ 'CouponTypeID "' + ISNULL(CouponTypeExternalId, 'NULL') + '" and '
					+ 'CouponID "' + ISNULL(CouponExternalId, 'NULL') + '" '
					+ 'does not exist.'
				ELSE ''
			END
			+ DataProcessing.GetErrorIfValueNotExists(DBAdditionalPaymentTypeGroupID, 0, 'SupplementalCardTypeID', AdditionalCardTypeExternalId, ' ')
			+ CASE WHEN PaymentOrder > 1
				THEN ' PaymentOrder = 1 does not exists.'
				ELSE ''
			END
			+ CASE WHEN ISNULL(PaymentGrossAmountByCustomer, 0.0) = 0.0
				THEN ' PaymentGrossAmountByCustomer must be <> 0.0 in cash payment.'
				ELSE ''
			END
			+ Common.GetEndLine()
		FROM #Sale S
		WHERE (DBAdditionalCardID IS NULL
				AND AdditionalCardExternalNumber IS NOT NULL
			)
			OR (DBAuthorizationTypeID IS NULL
				AND AuthorizationTypeExternalId IS NOT NULL
			)
			OR (DBBonusCardID IS NULL
				AND BonusCardExternalNumber IS NOT NULL
			)
			OR (DBBonusPaymentTypeGroupID IS NULL
				AND BonusCardTypeExternalId IS NOT NULL
			)
			OR DBCurrencyID IS NULL
			OR (DBInvoiceCardID IS NULL
				AND InvoiceCardExternalNumber IS NOT NULL
			)
			OR DBPaymentTypeGroupID IS NULL
			OR (DBAdditionalPaymentTypeGroupID IS NULL
				AND AdditionalCardTypeExternalId IS NOT NULL
			)
			OR (PaymentOrder > 1
				AND NOT EXISTS (SELECT 1 FROM #Sale WHERE ExternalId = S.ExternalId AND PaymentOrder = 1)
			)
			OR (DBPaymentTypeGroupID = '11'
				AND PaymentGrossAmount <> 0.0
				AND ISNULL(PaymentGrossAmountByCustomer, 0.0) = 0.0
			)

		SELECT @ValidationMessage += 'Item ' + CAST([Order] AS nvarchar) + ' within sale ' + CAST(SaleExternalId AS nvarchar) + ' -'
			+ CASE WHEN (DBCouponPaymentTypeGroupID IS NULL
					AND (CouponTypeExternalId IS NOT NULL
						OR CouponExternalId IS NOT NULL
					)
				)
				THEN ' Combination of attributes '
					+ 'CouponTypeID "' + ISNULL(CouponTypeExternalId, 'NULL') + '" and '
					+ 'CouponID "' + ISNULL(CouponExternalId, 'NULL') + '" '
					+ 'does not exist.'
				ELSE ''
			END
			+ DataProcessing.GetErrorIfValueNotExists(DBFuelTankID, 0, 'SaleItemTankNumber', FuelTankNumber, ' ')
			+ DataProcessing.GetErrorIfValueNotExists(DBGoodsID, 1, 'GoodsID', GoodsNumber, ' ')
			+ DataProcessing.GetErrorIfValueNotExists(DBOperationModeID, 0, 'SaleItemOpMode', OperationModeExternalId, ' ')
			+ DataProcessing.GetErrorIfValueNotExists(DBExciseTaxUnitID, 0, 'ConsTaxUnitID', ExciseTaxUnitExternalId, ' ')
			+ DataProcessing.GetErrorIfValueNotExists(DBAgencySupplierID, 0, 'SaleItemOwner', AgencySupplierNumber, ' ')
			+ DataProcessing.GetErrorIfValueNotExists(DBPromotionID, 0, 'PromotionsID', PromotionNumber, ' ')
			+ DataProcessing.GetErrorIfValueNotExists(DBCardTerminalGroupID, 0, 'CardTermGroup', CardTermGroupNumber, ' ')
			+ CASE WHEN GrossAmount <> 0.0 AND NetAmount = 0.0 AND ISNULL(TotalDiscount, 0.0) = 0.0 THEN ' SaleItemNetto cannot be 0.0 when SaleItemBrutto <> 0.0.' ELSE '' END
			+ Common.GetEndLine()
		FROM #SaleItem
		WHERE (DBCouponPaymentTypeGroupID IS NULL
				AND (CouponTypeExternalId IS NOT NULL
					OR CouponExternalId IS NOT NULL
				)
			)
			OR (DBFuelTankID IS NULL
				AND FuelTankNumber IS NOT NULL
			)
			OR DBGoodsID IS NULL
			OR (DBOperationModeID IS NULL
				AND OperationModeExternalId IS NOT NULL
			)
			OR (DBExciseTaxUnitID IS NULL
				AND ExciseTaxUnitExternalId IS NOT NULL
			)
			OR (DBAgencySupplierID IS NULL
				AND AgencySupplierNumber IS NOT NULL
			)
			OR (DBPromotionID IS NULL
				AND PromotionNumber IS NOT NULL
			)
			OR (DBCardTerminalGroupID IS NULL
				AND CardTermGroupNumber IS NOT NULL
			)
			OR (NetAmount = 0.0
				AND GrossAmount <> 0.0
				AND ISNULL(TotalDiscount, 0.0) = 0.0
			)

		SELECT @ValidationMessage += 'Loyalty card ' + CardNumber + ' within sale ' + CAST(SaleExternalId AS nvarchar) + ' -'
			+ DataProcessing.GetErrorIfValueNotExists(DBLoyaltyCardID, 0, 'CardEvidenceNumber', LoyaltyCardID, ' ')
			+ DataProcessing.GetErrorIfValueNotExists(DBLoyaltyCustomerID, 0, 'CustomerNumber', LoyaltyCustomerID, ' ')
			+ Common.GetEndLine()
		FROM @LoyaltySale
		WHERE (DBLoyaltyCardID IS NULL
				AND LoyaltyCardID IS NOT NULL
			)
			OR (DBLoyaltyCustomerID IS NULL
				AND LoyaltyCustomerID IS NOT NULL
			)

		SELECT @ValidationMessage += 'Loyalty item ' + CAST(SaleItemOrder AS nvarchar) + ' within sale ' + CAST(SaleExternalId AS nvarchar) + ' -'
			+ DataProcessing.GetErrorIfValueNotExists(DBAccrualProfileID, 0, 'EarnProfileNumber', AccrualProfileID, ' ')
			+ DataProcessing.GetErrorIfValueNotExists(DBRedemptionDiscountTypeID, 0, 'DiscountSubtype', RedemptionDiscountTypeSecondaryExternalId, ' ')
			+ DataProcessing.GetErrorIfValueNotExists(DBRedemptionProfileID, 0, 'BurnProfileNumber', RedemptionProfileID, ' ')
			+ Common.GetEndLine()
		FROM @LoyaltySaleItem
		WHERE (DBAccrualProfileID IS NULL
				AND AccrualProfileID IS NOT NULL
			)
			OR (DBRedemptionDiscountTypeID IS NULL
				AND RedemptionDiscountTypeSecondaryExternalId < 2
			)
			OR (DBRedemptionProfileID IS NULL
				AND RedemptionProfileID IS NOT NULL
			)

		SELECT @ValidationMessage += 'Loyalty card ' + CardNumber + ' within sale ' + CAST(SaleExternalId AS nvarchar) + ' -'
			+ DataProcessing.GetErrorIfValueNotExists(DBLoyaltyPointTypeID, 1, 'LoyaltyPointsType', LoyaltyPointTypeID, ' ')
			+ DataProcessing.GetErrorIfValueNotExists(DBPromotionID, 0, 'PromotionID', PromotionNumber, ' ')
			+ Common.GetEndLine()
		FROM @AccruedLoyaltyPoint
		WHERE DBLoyaltyPointTypeID IS NULL
			OR (DBPromotionID IS NULL
				AND PromotionNumber IS NOT NULL
			)

		SELECT @ValidationMessage += 'Issued coupon ' + CAST(Number AS nvarchar) + ' within sale ' + CAST(SaleExternalId AS nvarchar) + ' -'
			+ CASE WHEN (DBCouponPaymentTypeGroupID IS NULL)
				THEN ' Combination of attributes '
					+ 'CouponTypeID "' + ISNULL(CouponTypeExternalId, 'NULL') + '" and '
					+ 'CouponID "' + ISNULL(CouponExternalId, 'NULL') + '" '
					+ 'does not exist.'
				ELSE ''
			END
			+ Common.GetEndLine()
		FROM @IssuedCoupon
		WHERE DBCouponPaymentTypeGroupID IS NULL

		SELECT @ValidationMessage += 'Applied promotions within sale ' + CAST(SaleExternalId AS nvarchar) + ' -'
			+ DataProcessing.GetErrorIfValueNotExists(DBPromotionID, 1, 'PromotionsID', PromotionNumber, ' ')
			+ Common.GetEndLine()
		FROM @AppliedPromotion
		WHERE DBPromotionID IS NULL

		SELECT @ValidationMessage += 'Returned cash within sale ' + CAST(SaleExternalId AS nvarchar) + ' -'
			+ DataProcessing.GetErrorIfValueNotExists(DBCurrencyID, 1, 'ReturnedCurrencyID', ClientAppCurrencyID, ' ')
			+ Common.GetEndLine()
		FROM @ReturnedCash
		WHERE DBCurrencyID IS NULL

		SELECT @ValidationMessage += 'Deleted item ' + CAST(ExternalId AS nvarchar) + ' -'
			+ DataProcessing.GetErrorIfValueNotExists(DBGoodsID, 1, 'GoodsID', GoodsNumber, ' ')
			+ Common.GetEndLine()
		FROM @DeletedSaleItem
		WHERE DBGoodsID IS NULL

		SELECT @ValidationMessage += 'Cash movement ' + CAST(ExternalId AS nvarchar) + ' -'
			+ DataProcessing.GetErrorIfValueNotExists(DBCardPaymentTypeGroupID, 0, 'CashMoveCardTypeID', CardTypeExternalId, ' ')
			+ CASE WHEN (DBCashMovementTypeID IS NULL)
				THEN ' Combination of attributes '
					+ 'CashMoveTypeNumber "' + ISNULL(CAST(CashMovementTypeExternalId AS nvarchar), 'NULL') + '" and '
					+ 'CashMoveTypeSign "' + ISNULL(CAST(CashMovementTypeExternalSign AS nvarchar), 'NULL') + '" '
					+ 'does not exist.'
				ELSE ''
			END
			+ DataProcessing.GetErrorIfValueNotExists(DBCurrencyID, 1, 'CurrencyID', ClientAppCurrencyID, ' ')
			+ Common.GetEndLine()
		FROM @CashMovement
		WHERE (DBCardPaymentTypeGroupID IS NULL
				AND CardTypeExternalId IS NOT NULL
			)
			OR DBCashMovementTypeID IS NULL
			OR DBCurrencyID IS NULL

		IF (OBJECT_ID('tempdb..#CustomerUpdateValidation','U') IS NOT NULL)
			DROP TABLE #CustomerUpdateValidation;

		CREATE TABLE #CustomerUpdateValidation (
			SaleExternalId int,
			SaleNumber smallint,
			SalePosNumber tinyint,
			SaleClosed datetime2(3),
			SaleID bigint,
			SalePaymentOrder tinyint,
			Number smallint,
			PosNumber tinyint,
			Closed datetime2(3)
		)

		INSERT INTO #CustomerUpdateValidation (SaleExternalId, SaleNumber, SalePosNumber, SaleClosed, SaleID, SalePaymentOrder, Number, PosNumber, Closed)
		SELECT
			CU.SaleExternalId,
			CU.SaleNumber,
			CU.PosNumber AS SalePosNumber,
			CU.SaleClosed,
			S.ID,
			ISNULL(S.PaymentOrder, 0) AS PaymentOrder,
			ISNULL(S.Number, -1) AS Number,
			ISNULL(S.PosNumber, 0) AS PosNumber,
			ISNULL(S.Closed, '1753-01-01') AS Closed
		FROM @CustomerUpdate CU
			LEFT OUTER JOIN Sale.Sale S ON S.ExternalId = CU.SaleExternalId
				AND S.PetrolStationID = @PetrolStationID

		SELECT
			@ValidationMessage += 'CustomerUpdate with ExternalId ' + CAST(CUV.SaleExternalId AS nvarchar)
			+ CASE WHEN CUV.SaleID IS NULL
				THEN ' does not exist.'
				ELSE ' =>'
			END
			+ ' Not found attributes in Sale: '
			+ CASE WHEN CUV.SaleNumber <> CUV.Number
				THEN 'SaleNumber ' + CAST(CUV.SaleNumber AS nvarchar) + '; '
				ELSE ''
			END
			+ CASE WHEN CUV.SalePosNumber <> CUV.PosNumber
				THEN 'SalePosNumber ' + CAST(CUV.SalePosNumber AS nvarchar) + '; '
				ELSE ''
			END
			+ CASE WHEN CUV.SaleClosed <> CUV.Closed
				THEN 'SaleClosed ' + CAST(CUV.SaleClosed AS nvarchar) + '; '
				ELSE ''
			END
			+ Common.GetEndLine()
		FROM #CustomerUpdateValidation CUV
		WHERE CUV.SaleID IS NULL
			OR CUV.SaleNumber <> CUV.Number
			OR CUV.SalePosNumber <> CUV.PosNumber
			OR CUV.SaleClosed <> CUV.Closed

		IF (OBJECT_ID('tempdb..#FiscalRegistrationUpdateValidation','U') IS NOT NULL)
			DROP TABLE #FiscalRegistrationUpdateValidation;

		CREATE TABLE #FiscalRegistrationUpdateValidation (
			SaleExternalId int,
			SaleNumber smallint,
			SalePosNumber tinyint,
			SaleClosed datetime2(3),
			BusinessPremiseNumber int,
			ReceiptNumberEs varchar(30),
			ReceiptNumberEet varchar(30),
			TaxNumber varchar(20),
			MandatingTaxNumber varchar(20),
			SaleID bigint,
			Number smallint,
			PosNumber tinyint,
			Closed datetime2(3),
			BusinessPremiseId int,
			ReceiptNumber varchar(30),
			ExportedReceiptNumber varchar(30),
			TaxpayerTaxNumber varchar(20),
			AppointingTaxpayerTaxNumber varchar(20),
			FiscalRegistrationID bigint
		)

		INSERT INTO #FiscalRegistrationUpdateValidation (SaleExternalId, SaleNumber, SalePosNumber, SaleClosed, BusinessPremiseNumber, ReceiptNumberEs, ReceiptNumberEet, TaxNumber, MandatingTaxNumber, SaleID, Number, PosNumber, Closed, BusinessPremiseId, ReceiptNumber, ExportedReceiptNumber, TaxpayerTaxNumber, AppointingTaxpayerTaxNumber, FiscalRegistrationID)
		SELECT
			FRU.SaleExternalId,
			ISNULL(FRU.SaleNumber, -1) AS SaleNumber,
			ISNULL(FRU.PosNumber, 0) AS SalePosNumber,
			ISNULL(FRU.SaleClosed, '1753-01-01') AS SaleClosed,
			ISNULL(FRU.BusinessPremiseNumber, -1) AS BusinessPremiseNumber,
			ISNULL(FRU.ReceiptNumberEs, SPACE(0)) AS ReceiptNumberEs,
			ISNULL(FRU.ReceiptNumberEet, SPACE(0)) AS ReceiptNumberEet,
			ISNULL(FRU.TaxNumber, SPACE(0)) AS TaxNumber,
			ISNULL(FRU.MandatingTaxNumber, SPACE(0)) AS MandatingTaxNumber,
			S.ID AS SaleID,
			ISNULL(S.Number, -1) AS Number,
			ISNULL(S.PosNumber, 0) AS PosNumber,
			ISNULL(S.Closed, '1753-01-01') AS Closed,
			ISNULL(FR.BusinessPremisesId, -1) AS BusinessPremisesId,
			ISNULL(FR.ReceiptNumber, SPACE(0)) AS ReceiptNumber,
			ISNULL(FR.ExportedReceiptNumber, SPACE(0)) AS ExportedReceiptNumber,
			ISNULL(FR.TaxpayerTaxNumber, SPACE(0)) AS TaxpayerTaxNumber,
			ISNULL(FR.AppointingTaxpayerTaxNumber, SPACE(0)) AS AppointingTaxpayerTaxNumber,
			FR.ID AS FiscalRegistrationID
		FROM @FiscalRegistrationUpdate FRU
			LEFT OUTER JOIN Sale.Sale S ON S.ExternalId = FRU.SaleExternalId
				AND S.PetrolStationID = @PetrolStationID
			LEFT OUTER JOIN Sale.FiscalRegistration FR ON FR.SaleID = S.ID
				AND FR.SalePaymentOrder = S.PaymentOrder
				AND FR.ExportedReceiptNumber = FRU.ReceiptNumberEet

		SELECT
			@ValidationMessage += 'FiscalRegistrationUpdate with ExternalId ' + CAST(FRUV.SaleExternalId AS nvarchar)
			+ CASE WHEN FRUV.SaleID IS NULL
				THEN ' does not exist in Sale.'
				ELSE ''
			END
			+ CASE WHEN FRUV.FiscalRegistrationID IS NULL
				THEN ' does not exist in FiscalRegistration.'
				ELSE ''
			END
			+ ' With attributes: '
			+ CASE WHEN FRUV.SaleNumber <> FRUV.Number
				THEN 'SaleNumber ' + CAST(FRUV.SaleNumber AS nvarchar) + ' in Sale; '
				ELSE ''
			END
			+ CASE WHEN FRUV.SalePosNumber <> FRUV.PosNumber
				THEN 'SalePosNumber ' + CAST(FRUV.SalePosNumber AS nvarchar) + ' in Sale; '
				ELSE ''
			END
			+ CASE WHEN FRUV.SaleClosed <> FRUV.Closed
				THEN 'SaleClosed ' + CAST(FRUV.SaleClosed AS nvarchar) + ' in Sale; '
				ELSE ''
			END
			+ CASE WHEN FRUV.BusinessPremiseId <> FRUV.BusinessPremiseNumber
				THEN 'BusinessPremiseNumber ' + CAST(FRUV.BusinessPremiseNumber AS nvarchar) + ' in FiscalRegistration; '
				ELSE ''
			END
			+ CASE WHEN FRUV.ReceiptNumber <> FRUV.ReceiptNumberEs
				THEN 'ReceiptNumberEs ' + FRUV.ReceiptNumberEs + ' in FiscalRegistration; '
				ELSE ''
			END
			+ CASE WHEN FRUV.ExportedReceiptNumber <> FRUV.ReceiptNumberEet
				THEN 'ReceiptNumberEet ' + FRUV.ReceiptNumberEet + ' in FiscalRegistration; '
				ELSE ''
			END
			+ CASE WHEN FRUV.TaxpayerTaxNumber <> FRUV.TaxNumber
				THEN 'TaxNumber ' + FRUV.TaxNumber + ' in FiscalRegistration; '
				ELSE ''
			END
			+ CASE WHEN FRUV.AppointingTaxpayerTaxNumber <> FRUV.MandatingTaxNumber
				THEN 'MandatingTaxNumber ' + FRUV.MandatingTaxNumber + ' in FiscalRegistration; '
				ELSE ''
			END
			+ Common.GetEndLine()
		FROM #FiscalRegistrationUpdateValidation FRUV
		WHERE FRUV.SaleID IS NULL
			OR FRUV.FiscalRegistrationID IS NULL
			OR FRUV.SaleNumber <> FRUV.Number
			OR FRUV.SalePosNumber <> FRUV.PosNumber
			OR FRUV.SaleClosed <> FRUV.Closed
			OR FRUV.BusinessPremiseId <> FRUV.BusinessPremiseNumber
			OR FRUV.ReceiptNumber <> FRUV.ReceiptNumberEs
			OR FRUV.ExportedReceiptNumber <> FRUV.ReceiptNumberEet
			OR FRUV.TaxpayerTaxNumber <> FRUV.TaxNumber
			OR FRUV.AppointingTaxpayerTaxNumber <> FRUV.MandatingTaxNumber

		IF (@ValidationMessage <> '')
		BEGIN
			RAISERROR(@ValidationMessage, 16, 1)
		END
		-- Konec validace --

		-- Ulozit dialog
		BEGIN TRANSACTION ImportDialogXmlDataSALES_v6_1

		;WITH CTE_Shift AS (
			SELECT
				SH.ID AS ShiftID,
				TAB.NodeId,
				TAB.PetrolStationID,
				TAB.Number,
				TAB.Date,
				TAB.PosNumber,
				TAB.Opened,
				TAB.OpenedBy,
				TAB.Closed,
				TAB.ClosedBy,
				Common.GetDateTime2() AS Processed,
				@ProcessUserID AS ProcessedBy
			FROM @Shift TAB
				LEFT OUTER JOIN Sale.Shift SH ON SH.PetrolStationID = TAB.PetrolStationID
					AND SH.Date = TAB.Date
					AND SH.Number = TAB.Number
					AND SH.PosNumber = TAB.PosNumber
		)
		MERGE Sale.Shift TRG
		USING CTE_Shift SRC ON SRC.ShiftID = TRG.ID
		WHEN MATCHED THEN
			UPDATE SET
				Closed = SRC.Closed,
				ClosedBy = SRC.ClosedBy,
				Modified = SRC.Processed,
				ModifiedBy = SRC.ProcessedBy
		WHEN NOT MATCHED THEN
			INSERT (
				PetrolStationID,
				Number,
				Date,
				PosNumber,
				Opened,
				OpenedBy,
				Closed,
				ClosedBy,
				Created,
				CreatedBy
			)
			VALUES (
				SRC.PetrolStationID,
				SRC.Number,
				SRC.Date,
				SRC.PosNumber,
				SRC.Opened,
				SRC.OpenedBy,
				SRC.Closed,
				SRC.ClosedBy,
				SRC.Processed,
				SRC.ProcessedBy
			)
		OUTPUT
			SRC.NodeId,
			inserted.ID
		INTO @ShiftIDs (
			NodeId,
			ID
		);

		WITH CTE_ShiftCash AS (
			SELECT
				SHID.ID AS ShiftID,
				TAB.DBCurrencyID AS CurrencyID,
				SUM(TAB.OpeningAmount) AS OpeningAmount,
				SUM(TAB.ClosingAmount) AS ClosingAmount,
				Common.GetDateTime2() AS Processed,
				@ProcessUserID AS ProcessedBy
			FROM @ShiftCash TAB
				INNER JOIN @ShiftIDs SHID ON SHID.NodeId = TAB.ShiftNodeId
			GROUP BY
				SHID.ID,
				TAB.DBCurrencyID
		)
		MERGE Sale.ShiftCash TRG
		USING CTE_ShiftCash SRC ON SRC.ShiftID = TRG.ShiftID
			AND SRC.CurrencyID = TRG.CurrencyID
		WHEN MATCHED THEN
			UPDATE SET
				ClosingAmount = SRC.ClosingAmount,
				Modified = SRC.Processed,
				ModifiedBy = SRC.ProcessedBy
		WHEN NOT MATCHED THEN
			INSERT (
				ShiftID,
				CurrencyID,
				OpeningAmount,
				ClosingAmount,
				Created,
				CreatedBy
			)
			VALUES (
				SRC.ShiftID,
				SRC.CurrencyID,
				SRC.OpeningAmount,
				SRC.ClosingAmount,
				SRC.Processed,
				SRC.ProcessedBy
			)
		;

		MERGE Sale.Sales TRG
		USING @UpdatedSaleIDs SRC ON SRC.ID = TRG.ID
			AND SRC.PaymentOrder = TRG.PaymentOrder
		WHEN MATCHED THEN
			UPDATE SET
				ReceiptModificationTypeID = SRC.ReceiptModificationTypeID,
				ReceiptTypeID = SRC.ReceiptTypeID,
				CustomerCity = SRC.CustomerCity,
				CustomerCountry = SRC.CustomerCountry,
				CustomerIdentificationNumber = SRC.CustomerIdentificationNumber,
				CustomerName = SRC.CustomerName,
				CustomerStreet = SRC.CustomerStreet,
				CustomerTaxNumber = SRC.CustomerTaxNumber,
				CustomerZip = SRC.CustomerZip,
				GreenCustomerNumber = SRC.GreenCustomerNumber,
				SaleDetailModified = Common.GetDateTime2(),
				SaleDetailModifiedBy = @ProcessUserID
		;

		SELECT @MaxSaleID = ISNULL(MAX(ID), 0)
		FROM Sale.Sale

		INSERT INTO Sale.Sales (
			ID,
			PaymentOrder,
			AdditionalCardID,
			AuthorizationTypeID,
			BonusCardID,
			BonusPaymentTypeGroupID,
			CurrencyID,
			ImportedBatchID,
			InvoiceCardID,
			PaymentTypeGroupID,
			PetrolStationID,
			ExternalId,
			Number,
			PosNumber,
			Closed,
			ReceiptNumber,
			ReceiptGrossAmount,
			PaymentGrossAmount,
			CardTrack,
			BonusCardTrack,
			AdditionalCardTrack,
			TransactionId,
			Authorized,
			AuthorizationCode,
			CardExpiration,
			Km,
			DriverId,
			Licenceplate,
			IsInternalConsumption,
			SaleCreated,
			SaleCreatedBy,
			UniCustomerID,

			SaleID,
			SalePaymentOrder,
			AdditionalPaymentTypeGroupID,
			ReceiptModificationTypeID,
			ReceiptTypeID,
			ShiftID,
			CancelType,
			CardOwnerAddress,
			CardOwnerName,
			CouponBarcode,
			CouponHash,
			CouponNominalValue,
			CouponNumber,
			Coupons,
			CouponSecondaryId,
			CustomerCity,
			CustomerCountry,
			CustomerIdentificationNumber,
			CustomerName,
			CustomerNumber,
			CustomerStreet,
			CustomerTaxNumber,
			CustomerZip,
			DailySettlementDate,
			ExchangeRate,
			FiscalNumber,
			GreenCustomerNumber,
			Hash,
			LoyaltyBurnTransactionId,
			LoyaltyEarnTransactionId,
			Note,
			OrderNumber,
			PaymentGrossAmountByCustomer,
			PaymentPart,
			PartnerIdentificationNumber,
			PinStatus,
			PosUserName,
			PosUserNumber,
			ReferencedSaleExternalId,
			ReferencedSaleReceiptNumber,
			ShellFleetId,
			TableNumber,
			TerminalBatchNumber,
			TerminalId,
			VipCustomerName,
			VipCustomerNumber,
			VipRequestId,
			IsCardManual,
			IsDccTransaction,
			IsKioskSale,
			IsLocalCustomer,
			IsMobilePayment,
			IsOptSale,
			IsPriorCanceledSale,
			IsVipDiscountOnline,
			SaleDetailCreated,
			SaleDetailCreatedBy,
			ClosedDate
		)
		OUTPUT
			inserted.ExternalId,
			inserted.ID,
			inserted.PaymentOrder,
			inserted.PaymentPart,
			inserted.PaymentTypeGroupID,
			CAST(inserted.Closed AS date)
		INTO @SaleIDs (
			ExternalId,
			ID,
			PaymentOrder,
			PaymentPart,
			PaymentTypeGroupID,
			ClosedDate
		)
		SELECT
			@MaxSaleID + DENSE_RANK() OVER (ORDER BY TAB.ExternalId),
			TAB.PaymentOrder,
			TAB.DBAdditionalCardID,
			TAB.DBAuthorizationTypeID,
			TAB.DBBonusCardID,
			TAB.DBBonusPaymentTypeGroupID,
			TAB.DBCurrencyID,
			TAB.ImportedBatchID,
			TAB.DBInvoiceCardID,
			TAB.DBPaymentTypeGroupID,
			TAB.PetrolStationID,
			TAB.ExternalId,
			TAB.Number,
			TAB.PosNumber,
			TAB.Closed,
			TAB.ReceiptNumber,
			TAB.ReceiptGrossAmount,
			TAB.PaymentGrossAmount,
			TAB.CardTrack,
			TAB.BonusCardTrack,
			TAB.AdditionalCardTrack,
			TAB.TransactionId,
			TAB.Authorized,
			TAB.AuthorizationCode,
			TAB.CardExpiration,
			TAB.Km,
			TAB.DriverId,
			TAB.Licenceplate,
			TAB.IsInternalConsumption,
			Common.GetDateTime2(),
			@ProcessUserID,
			@UniCustomerID,

			@MaxSaleID + DENSE_RANK() OVER (ORDER BY TAB.ExternalId),
			TAB.PaymentOrder,
			TAB.DBAdditionalPaymentTypeGroupID,
			TAB.DBReceiptModificationTypeID,
			TAB.DBReceiptTypeID,
			SH.ID,
			TAB.CancelType,
			TAB.CardOwnerAddress,
			TAB.CardOwnerName,
			TAB.CouponBarcode,
			TAB.CouponHash,
			TAB.CouponNominalValue,
			TAB.CouponNumber,
			TAB.Coupons,
			TAB.CouponSecondaryId,
			TAB.CustomerCity,
			TAB.CustomerCountry,
			TAB.CustomerIdentificationNumber,
			TAB.CustomerName,
			TAB.CustomerNumber,
			TAB.CustomerStreet,
			TAB.CustomerTaxNumber,
			TAB.CustomerZip,
			TAB.DailySettlementDate,
			TAB.ExchangeRate,
			TAB.FiscalNumber,
			TAB.GreenCustomerNumber,
			TAB.Hash,
			TAB.LoyaltyBurnTransactionId,
			TAB.LoyaltyEarnTransactionId,
			TAB.Note,
			TAB.OrderNumber,
			TAB.PaymentGrossAmountByCustomer,
			TAB.PaymentPart,
			TAB.PartnerIdentificationNumber,
			TAB.PinStatus,
			TAB.PosUserName,
			TAB.PosUserNumber,
			TAB.ReferencedSaleExternalId,
			TAB.ReferencedSaleReceiptNumber,
			TAB.ShellFleetId,
			TAB.TableNumber,
			TAB.TerminalBatchNumber,
			TAB.TerminalId,
			TAB.VipCustomerName,
			TAB.VipCustomerNumber,
			TAB.VipRequestId,
			TAB.IsCardManual,
			TAB.IsDccTransaction,
			TAB.IsKioskSale,
			TAB.IsLocalCustomer,
			TAB.IsMobilePayment,
			TAB.IsOptSale,
			TAB.IsPriorCanceledSale,
			TAB.IsVipDiscountOnline,
			Common.GetDateTime2(),
			@ProcessUserID,
			CAST(TAB.Closed AS date)
		FROM #Sale TAB
			LEFT OUTER JOIN Sale.Shift SH ON SH.PetrolStationID = TAB.PetrolStationID
				AND SH.Number = TAB.ShiftNumber
				AND SH.Date = TAB.ShiftDate
				AND ((@PetrolStationTypeID = 'O' AND SH.PosNumber = TAB.PosNumber)
					OR @PetrolStationTypeID <> 'O'
				)
		WHERE TAB.IsUpdateEnabled = 0

		INSERT INTO @SaleCancelation (
			SaleID,
			SalePaymentOrder,
			CanceledSaleID,
			CanceledSalePaymentOrder,
			ReturnedSaleID,
			ReturnedSalePaymentOrder
		)
		SELECT
			SID.ID,
			SID.PaymentOrder,
			CASE WHEN (TAB.IsCancel = 1) THEN RC.ID ELSE NULL END,
			CASE WHEN (TAB.IsCancel = 1) THEN RC.PaymentOrder ELSE NULL END,
			CASE WHEN (TAB.IsReturn = 1) THEN RR.ID ELSE NULL END,
			CASE WHEN (TAB.IsReturn = 1) THEN RR.PaymentOrder ELSE NULL END
		FROM #Sale TAB
			INNER JOIN @SaleIDs SID ON SID.ExternalId = TAB.ExternalId
			CROSS APPLY (
				SELECT
					ID AS PetrolStationID,
					CAST(SUBSTRING(TAB.ReferencedSaleReceiptNumber, 4, 2) AS tinyint) PosNumber,
					CAST(LEFT(CAST(YEAR(Common.GetDate()) as varchar(4)), 2) + SUBSTRING(TAB.ReferencedSaleReceiptNumber, 6, 2) + '-' + SUBSTRING(TAB.ReferencedSaleReceiptNumber, 8,2) + '-' + SUBSTRING(TAB.ReferencedSaleReceiptNumber, 10, 2) AS date) ClosedDate,
					CAST(RIGHT(TAB.ReferencedSaleReceiptNumber, 4) AS int) AS SaleNumber
				FROM PetrolStation.PetrolStation 
				WHERE Number = CAST(LEFT(TAB.ReferencedSaleReceiptNumber, 3) AS int)
			) RET
			LEFT OUTER JOIN Sale.Sale RC ON RC.PetrolStationID = TAB.PetrolStationID
				AND RC.ExternalId = TAB.ReferencedSaleExternalId
				AND RC.PaymentOrder = TAB.PaymentOrder
				AND SID.PaymentOrder = TAB.PaymentOrder
				AND TAB.IsCancel = 1
			LEFT OUTER JOIN Sale.Sale RR ON RR.PetrolStationID = RET.PetrolStationID
				AND RR.PosNumber = RET.PosNumber
				AND RR.ClosedDate = RET.ClosedDate
				AND RR.Number = RET.SaleNumber
				AND RR.PaymentOrder = TAB.PaymentOrder
				AND SID.PaymentOrder = TAB.PaymentOrder
				AND TAB.IsReturn = 1
		WHERE TAB.ReferencedSaleReceiptNumber IS NOT NULL

		DELETE FROM @SaleCancelation WHERE CanceledSaleID IS NULL AND ReturnedSaleID IS NULL

		MERGE Sale.Sale TRG
		USING @SaleCancelation SRC ON SRC.SaleID = TRG.ID
			AND SRC.SalePaymentOrder = TRG.PaymentOrder
		WHEN MATCHED THEN
			UPDATE SET
				CanceledSaleID = SRC.CanceledSaleID,
				CanceledSalePaymentOrder = SRC.CanceledSalePaymentOrder,
				ReturnedSaleID = SRC.ReturnedSaleID,
				ReturnedSalePaymentOrder = SRC.ReturnedSalePaymentOrder,
				Modified = Common.GetDateTime2(),
				ModifiedBy = @ProcessUserID
		;

		MERGE Sale.Sale TRG
		USING (
			SELECT
				SaleID,
				SalePaymentOrder,
				CanceledSaleID,
				CanceledSalePaymentOrder,
				ReturnedSaleID,
				ReturnedSalePaymentOrder
			FROM (
				SELECT
					SaleID,
					SalePaymentOrder,
					CanceledSaleID,
					CanceledSalePaymentOrder,
					ReturnedSaleID,
					ReturnedSalePaymentOrder,
					ROW_NUMBER() OVER (PARTITION BY ISNULL(CanceledSaleID, ReturnedSaleID), ISNULL(CanceledSalePaymentOrder, ReturnedSalePaymentOrder) ORDER BY SaleID, SalePaymentOrder) [Order]
				FROM @SaleCancelation
			) X
			WHERE [Order] = 1
		) SRC ON SRC.CanceledSaleID = TRG.ID
			AND SRC.CanceledSalePaymentOrder = TRG.PaymentOrder
		WHEN MATCHED THEN
			UPDATE SET
				CancelSaleID = SRC.SaleID,
				CancelSalePaymentOrder = SRC.SalePaymentOrder,
				Modified = Common.GetDateTime2(),
				ModifiedBy = @ProcessUserID
		;

		UPDATE SD SET
				SD.CustomerName = CU.CustomerName,
				SD.CustomerNumber = CU.CustomerNumber,
				SD.CustomerTaxNumber = CU.CustomerTaxID,
				SD.CustomerStreet = CU.CustomerAddress,
				SD.CustomerCity = CU.CustomerCity,
				SD.CustomerCountry = CU.CustomerCountry,
				SD.CustomerZip = CU.CustomerZip
			FROM Sale.SaleDetail SD
				INNER JOIN #CustomerUpdateValidation CUV ON CUV.SaleID = SD.SaleID
					AND CUV.SalePaymentOrder = SD.SalePaymentOrder
				LEFT OUTER JOIN @CustomerUpdate CU ON CU.SaleExternalId = CUV.SaleExternalId
		;

		UPDATE FR SET
				FR.RequestStatus = FRU.RequestStatus,
				FR.FiscalIdentificationCode = FRU.FiscalIdentificationCode,
				FR.TaxpayerSecurityCode = FRU.TaxpayerSecurityCode,
				FR.TaxpayerSignatureCode = FRU.TaxpayerSignatureCode,
				FR.RequestErrorCode = FRU.ErrorCode,
				FR.RequestErrorMessage = FRU.ErrorMessage
			FROM Sale.FiscalRegistration FR
				INNER JOIN #FiscalRegistrationUpdateValidation FRUV ON FRUV.FiscalRegistrationID = FR.ID
				LEFT OUTER JOIN @FiscalRegistrationUpdate FRU ON FRU.SaleExternalId = FRUV.SaleExternalId
					AND FRU.ReceiptNumberEet = FRUV.ExportedReceiptNumber
		;

		INSERT INTO Sale.SaleItems (
			SaleID,
			SalePaymentOrder,
			[Order],
			CardTerminalGroupID,
			CouponPaymentTypeGroupID,
			FuelTankID,
			GoodsID,
			OperationModeID,
			EanCode,
			Quantity,
			GrossPrice,
			NetAmount,
			GrossAmount,
			VatRate,
			TotalDiscount,
			AverageCostAmount,
			CouponNumber,
			CouponExpiration,
			DispenserNumber,
			NozzleNumber,
			SaleItemCreated,
			SaleItemCreatedBy,
			PaymentTypeGroupID,
			PetrolStationID,
			UniCustomerID,
			ClosedDate,
			IsFuel,
			IsRounding,
			CouponSerialNumber,
			IsOnline,

			SaleItemSaleID,
			SaleItemSalePaymentOrder,
			SaleItemOrder,
			ExciseTaxUnitID,
			AgencySupplierID,
			PromotionID,
			AlternativeVatCode,
			FuelTemperature,
			PurchasePrice,
			NetAmountWithoutDiscount,
			GrossAmountWithoutDiscount,
			PromotionDiscount,
			BankCardDiscount,
			BankCardDiscountProfile,
			CarWashNumber,
			CarWashProgram,
			CarWashTransactionID,
			CarWashAdditionalInfoTypeID,
			CarWashAdditionalInfoValue,
			CustomerDiscount,
			CustomerDiscountProfile,
			CustomerCentralDiscount,
			CustomerCentralDiscountProfile,
			CustomerCentralDiscountCompensation,
			VipDiscount,
			VipDiscountProfile,
			VipDiscountProfileName,
			Nomenclature,
			ExciseTaxRate,
			ExciseTaxRateFactor,
			ExciseTaxAmount,
			CouponHash,
			ChargeType,
			ChargeCardNumber,
			ChargeApprovalCode,
			Charged,
			PromoAuthorizationCode,
			PromoAuthorizationCodeType,
			IsCouponOptBound,
			IsPriceEanScanned,
			IsTandem,
			SaleItemDetailCreated,
			SaleItemDetailCreatedBy
		)
		SELECT
			SID.ID,
			SID.PaymentOrder,
			TAB.[Order],
			TAB.DBCardTerminalGroupID,
			TAB.DBCouponPaymentTypeGroupID,
			TAB.DBFuelTankID,
			TAB.DBGoodsID,
			TAB.DBOperationModeID,
			TAB.EanCode,
			TAB.Quantity * SID.PaymentPart,
			TAB.GrossPrice,
			TAB.NetAmount * SID.PaymentPart,
			TAB.GrossAmount * SID.PaymentPart,
			TAB.VatRate,
			TAB.TotalDiscount * SID.PaymentPart,
			TAB.AverageCostAmount * SID.PaymentPart,
			TAB.CouponNumber,
			TAB.CouponExpiration,
			TAB.DispenserNumber,
			TAB.NozzleNumber,
			Common.GetDateTime2(),
			@ProcessUserID,
			SID.PaymentTypeGroupID,
			@PetrolStationID,
			@UniCustomerID,
			SID.ClosedDate,
			TAB.IsFuel,
			TAB.IsRounding,
			TAB.CouponSerialNumber,
			TAB.IsOnline,

			SID.ID,
			SID.PaymentOrder,
			TAB.[Order],
			TAB.DBExciseTaxUnitID,
			TAB.DBAgencySupplierID,
			TAB.DBPromotionID,
			TAB.AlternativeVatCode,
			TAB.FuelTemperature,
			TAB.PurchasePrice,
			TAB.NetAmountWithoutDiscount * SID.PaymentPart,
			TAB.GrossAmountWithoutDiscount * SID.PaymentPart,
			TAB.PromotionDiscount * SID.PaymentPart,
			TAB.BankCardDiscount * SID.PaymentPart,
			TAB.BankCardDiscountProfile,
			TAB.CarWashNumber,
			TAB.CarWashProgram,
			TAB.CarWashTransactionID,
			TAB.CarWashAdditionalInfoTypeID,
			TAB.CarWashAdditionalInfoValue,
			TAB.CustomerDiscount * SID.PaymentPart,
			TAB.CustomerDiscountProfile,
			TAB.CustomerCentralDiscount * SID.PaymentPart,
			TAB.CustomerCentralDiscountProfile,
			TAB.CustomerCentralDiscountCompensation * SID.PaymentPart,
			TAB.VipDiscount * SID.PaymentPart,
			TAB.VipDiscountProfile,
			TAB.VipDiscountProfileName,
			TAB.Nomenclature,
			TAB.ExciseTaxRate,
			TAB.ExciseTaxRateFactor,
			TAB.ExciseTaxAmount * SID.PaymentPart,
			TAB.CouponHash,
			TAB.ChargeType,
			TAB.ChargeCardNumber,
			TAB.ChargeApprovalCode,
			TAB.Charged,
			TAB.PromoAuthorizationCode,
			TAB.PromoAuthorizationCodeType,
			TAB.IsCouponOptBound,
			TAB.IsPriceEanScanned,
			TAB.IsTandem,
			Common.GetDateTime2(),
			@ProcessUserID
		FROM #SaleItem TAB
			INNER JOIN @SaleIDs SID ON SID.ExternalId = TAB.SaleExternalId

		INSERT INTO Sale.LoyaltySale (
			SaleID,
			SalePaymentOrder,
			LoyaltyCardID,
			LoyaltyCustomerID,
			CardNumber,
			IsOnline,
			IsVirtualCard,
			Created,
			CreatedBy
		)
		SELECT
			SID.ID,
			SID.PaymentOrder,
			TAB.DBLoyaltyCardID,
			TAB.DBLoyaltyCustomerID,
			TAB.CardNumber,
			TAB.IsOnline,
			TAB.IsVirtualCard,
			Common.GetDateTime2(),
			@ProcessUserID
		FROM @LoyaltySale TAB
			INNER JOIN @SaleIDs SID ON SID.ExternalId = TAB.SaleExternalId

		INSERT INTO Sale.LoyaltySaleItem (
			SaleItemSaleID,
			SaleItemSalePaymentOrder,
			SaleItemOrder,
			AccrualProfileID,
			RedemptionDiscountTypeID,
			RedemptionProfileID,
			AccruedPoints,
			RedeemedPoints,
			Discount,
			CompensationAmount,
			Created,
			CreatedBy
		)
		SELECT
			SID.ID,
			SID.PaymentOrder,
			TAB.SaleItemOrder,
			TAB.DBAccrualProfileID,
			TAB.DBRedemptionDiscountTypeID,
			TAB.DBRedemptionProfileID,
			TAB.AccruedPoints * SID.PaymentPart,
			TAB.RedeemedPoints * SID.PaymentPart,
			TAB.Discount * SID.PaymentPart,
			TAB.CompensationAmount * SID.PaymentPart,
			Common.GetDateTime2(),
			@ProcessUserID
		FROM @LoyaltySaleItem TAB
			INNER JOIN @SaleIDs SID ON SID.ExternalId = TAB.SaleExternalId

		INSERT INTO Sale.AccruedLoyaltyPoint (
			SaleID,
			SalePaymentOrder,
			[Order],
			LoyaltyPointTypeID,
			PromotionID,
			CardNumber,
			Quantity,
			IsOnline,
			Created,
			CreatedBy
		)
		SELECT
			SID.ID,
			SID.PaymentOrder,
			TAB.[Order],
			TAB.DBLoyaltyPointTypeID,
			TAB.DBPromotionID,
			TAB.CardNumber,
			TAB.Quantity * SID.PaymentPart,
			TAB.IsOnline,
			Common.GetDateTime2(),
			@ProcessUserID
		FROM @AccruedLoyaltyPoint TAB
			INNER JOIN @SaleIDs SID ON SID.ExternalId = TAB.SaleExternalId

		INSERT INTO Sale.UnknownCode (
			SaleID,
			SalePaymentOrder,
			[Order],
			Scanned,
			Code,
			Created,
			CreatedBy
		)
		SELECT
			SID.ID,
			SID.PaymentOrder,
			TAB.[Order],
			TAB.Scanned,
			TAB.Code,
			Common.GetDateTime2(),
			@ProcessUserID
		FROM @UnknownCode TAB
			INNER JOIN @SaleIDs SID ON SID.ExternalId = TAB.SaleExternalId

		INSERT INTO Sale.IssuedCoupon (
			SaleID,
			SalePaymentOrder,
			CouponPaymentTypeGroupID,
			Number,
			Barcode,
			NominalValue,
			Expiration,
			SecondaryId,
			RuleNumber,
			Created,
			CreatedBy
		)
		SELECT
			SID.ID,
			SID.PaymentOrder,
			TAB.DBCouponPaymentTypeGroupID,
			TAB.Number,
			TAB.Barcode,
			TAB.NominalValue,
			TAB.Expiration,
			TAB.SecondaryId,
			TAB.RuleNumber,
			Common.GetDateTime2(),
			@ProcessUserID
		FROM @IssuedCoupon TAB
			INNER JOIN @SaleIDs SID ON SID.ExternalId = TAB.SaleExternalId

		INSERT INTO Sale.AppliedPromotion (
			SaleID,
			SalePaymentOrder,
			PromotionID,
			Promotions,
			Created,
			CreatedBy
		)
		SELECT
			SID.ID,
			SID.PaymentOrder,
			TAB.DBPromotionID,
			TAB.Promotions * SID.PaymentPart,
			Common.GetDateTime2(),
			@ProcessUserID
		FROM @AppliedPromotion TAB
			INNER JOIN @SaleIDs SID ON SID.ExternalId = TAB.SaleExternalId

		INSERT INTO Sale.ReturnedCash (
			SaleID,
			SalePaymentOrder,
			CurrencyID,
			ExchangeRate,
			Amount,
			IsTerminalCashback,
			Created,
			CreatedBy
		)
		SELECT
			SID.ID,
			SID.PaymentOrder,
			TAB.DBCurrencyID,
			TAB.ExchangeRate,
			TAB.Amount * SID.PaymentPart,
			TAB.IsTerminalCashback,
			Common.GetDateTime2(),
			@ProcessUserID
		FROM @ReturnedCash TAB
			INNER JOIN @SaleIDs SID ON SID.ExternalId = TAB.SaleExternalId

		INSERT INTO Sale.DeletedSaleItem (
			GoodsID,
			PetrolStationID,
			ShiftID,
			ExternalId,
			Deleted,
			PosNumber,
			EanCode,
			Quantity,
			GrossPrice,
			GrossAmount,
			VatRate,
			AlternativeVatCode,
			Created,
			CreatedBy
		)
		SELECT
			TAB.DBGoodsID,
			TAB.PetrolStationID,
			SH.ID,
			TAB.ExternalId,
			TAB.Deleted,
			TAB.PosNumber,
			TAB.EanCode,
			TAB.Quantity,
			TAB.GrossPrice,
			TAB.GrossAmount,
			TAB.VatRate,
			TAB.AlternativeVatCode,
			Common.GetDateTime2(),
			@ProcessUserID
		FROM @DeletedSaleItem TAB
			LEFT OUTER JOIN Sale.Shift SH ON SH.PetrolStationID = TAB.PetrolStationID
				AND SH.Number = TAB.ShiftNumber
				AND SH.Date = TAB.ShiftDate

		INSERT INTO Sale.CashMovement (
			CardPaymentTypeGroupID,
			CashMovementTypeID,
			CurrencyID,
			PetrolStationID,
			ShiftID,
			ExternalId,
			Entered,
			Number,
			PosNumber,
			PosUserNumber,
			NetAmount,
			GrossAmount,
			VatRate,
			AlternativeVatCode,
			ExchangeRate,
			CardExtendedInfo,
			Note,
			IsCancel,
			IsCashAffected,
			IsSaldoAffected,
			IsTurnoverAffected,
			Created,
			CreatedBy,
			UniCustomerID
		)
		OUTPUT
			inserted.ExternalId,
			inserted.ID
		INTO @CashMovementIDs (
			ExternalId,
			ID
		)
		SELECT
			TAB.DBCardPaymentTypeGroupID,
			TAB.DBCashMovementTypeID,
			TAB.DBCurrencyID,
			TAB.PetrolStationID,
			SH.ID,
			TAB.ExternalId,
			TAB.Entered,
			TAB.Number,
			TAB.PosNumber,
			TAB.PosUserNumber,
			TAB.NetAmount,
			TAB.GrossAmount,
			TAB.VatRate,
			TAB.AlternativeVatCode,
			TAB.ExchangeRate,
			TAB.CardExtendedInfo,
			TAB.Note,
			TAB.IsCancel,
			TAB.IsCashAffected,
			TAB.IsSaldoAffected,
			TAB.IsTurnoverAffected,
			Common.GetDateTime2(),
			@ProcessUserID,
			PetrolStation.GetPetrolStationUniCustomerID(TAB.PetrolStationID)
		FROM @CashMovement TAB
			LEFT OUTER JOIN Sale.Shift SH ON SH.PetrolStationID = TAB.PetrolStationID
				AND SH.Number = TAB.ShiftNumber
				AND SH.Date = TAB.ShiftDate

		INSERT INTO Sale.CashMovementCoupon (
			CashMovementID,
			[Order],
			CouponPaymentTypeGroupID,
			Number,
			Hash,
			GrossAmount,
			Created,
			CreatedBy
		)
		SELECT
			CMID.ID,
			TAB.[Order],
			TAB.CouponPaymentTypeGroupID,
			TAB.Number,
			TAB.Hash,
			TAB.GrossAmount,
			Common.GetDateTime2(),
			@ProcessUserID
		FROM @CashMovementCoupon TAB
			INNER JOIN @CashMovementIDs CMID ON CMID.ExternalId = TAB.CashMovementExternalId

		INSERT INTO Sale.FiscalRegistration (
			CashMovementID,
			SaleID,
			SalePaymentOrder,
			[Order],
			BusinessPremisesId,
			ReceiptNumber,
			ExportedReceiptNumber,
			TaxpayerTaxNumber,
			AppointingTaxpayerTaxNumber,
			GrossAmount,
			NetAmountExemptFromVat,
			NetAmountBasicVatRate,
			NetAmountReducedVatRate,
			NetAmountSecondReducedVatRate,
			VatAmountBasicVatRate,
			VatAmountReducedVatRate,
			VatAmountSecondReducedVatRate,
			IntendedSubsequentDrawingGrossAmount,
			SubsequentDrawingGrossAmount,
			FiscalIdentificationCode,
			TaxpayerSecurityCode,
			TaxpayerSignatureCode,
			RequestStatus,
			RequestErrorCode,
			RequestErrorMessage,
			WarningMessage,
			Created,
			CreatedBy
		)
		SELECT
			CMID.ID AS CashMovementID,
			SID.ID AS SaleID,
			SID.PaymentOrder AS SalePaymentOrder,
			TAB.[Order],
			TAB.BusinessPremisesId,
			TAB.ReceiptNumber,
			TAB.ExportedReceiptNumber,
			TAB.TaxpayerTaxNumber,
			TAB.AppointingTaxpayerTaxNumber,
			TAB.GrossAmount * PP.PaymentPart,
			TAB.NetAmountExemptFromVat * PP.PaymentPart,
			TAB.NetAmountBasicVatRate * PP.PaymentPart,
			TAB.NetAmountReducedVatRate * PP.PaymentPart,
			TAB.NetAmountSecondReducedVatRate * PP.PaymentPart,
			TAB.VatAmountBasicVatRate * PP.PaymentPart,
			TAB.VatAmountReducedVatRate * PP.PaymentPart,
			TAB.VatAmountSecondReducedVatRate * PP.PaymentPart,
			TAB.IntendedSubsequentDrawingGrossAmount * PP.PaymentPart,
			TAB.SubsequentDrawingGrossAmount * PP.PaymentPart,
			TAB.FiscalIdentificationCode,
			TAB.TaxpayerSecurityCode,
			TAB.TaxpayerSignatureCode,
			TAB.RequestStatus,
			TAB.RequestErrorCode,
			TAB.RequestErrorMessage,
			WM.WarningMessage,
			Common.GetDateTime2() AS Created,
			@ProcessUserID AS CreatedBy
		FROM @FiscalRegistration TAB
			LEFT OUTER JOIN @SaleIDs SID ON SID.ExternalId = TAB.SaleExternalId
			LEFT OUTER JOIN @CashMovementIDs CMID ON CMID.ExternalId = TAB.CashMovementExternalId
			CROSS APPLY (
				SELECT ISNULL(SID.PaymentPart, 1.0) AS PaymentPart
			) PP
			OUTER APPLY (
				SELECT STUFF((
							SELECT Common.GetEndLine() + W.Code + ISNULL(' - ' + W.Message, '')
							FROM @FiscalRegistrationWarning W
							WHERE W.FiscalRegistrationNodeId = TAB.NodeId
							FOR XML PATH (''), TYPE
						).value('.', 'nvarchar(MAX)'), 1, LEN(Common.GetEndLine()), ''
					) AS WarningMessage
			) WM

		INSERT INTO Sale.RecipeComponent (
			SaleItemSaleID,
			SaleItemSalePaymentOrder,
			SaleItemOrder,
			AgencySupplierID,
			GoodsID,
			AverageCostAmount,
			Quantity,
			Created,
			CreatedBy
		)
		SELECT
			SID.ID,
			SID.PaymentOrder,
			TAB.SaleItemOrder,
			TAB.DBAgencySupplierID,
			TAB.DBGoodsID,
			TAB.AverageCostAmount,
			TAB.Quantity,
			Common.GetDateTime2(),
			@ProcessUserID
		FROM @RecipeComponent TAB
			INNER JOIN @SaleIDs SID ON SID.ExternalId = TAB.SaleExternalId
/*
		INSERT INTO Sale.MarketingText(
			SaleID,
			SalePaymentOrder,
			MarketingTextID,
			CodeType,
			CodeValue,
			Created,
			CreatedBy
		)
		SELECT
			SID.ID,
			SID.PaymentOrder,
			TAB.MarketingTextID,
			TAB.CodeType,
			TAB.CodeValue,
			Common.GetDateTime2(),
			@ProcessUserID
		FROM @MarketingText TAB
			INNER JOIN @SaleIDs SID ON SID.ExternalId = TAB.SaleExternalId
*/
		INSERT INTO Sale.CustomerUpdate(
			SaleID,
			SalePaymentOrder,
			SaleNumber,
			PosNumber,
			SaleClosed,
			CustomerName,
			CustomerNumber,
			CustomerTaxID,
			CustomerAddress,
			CustomerCity,
			CustomerCountry,
			CustomerZip,
			Created,
			CreatedBy
		)
		SELECT
			CUV.SaleID,
			CUV.SalePaymentOrder,
			TAB.SaleNumber,
			TAB.PosNumber,
			TAB.SaleClosed,
			TAB.CustomerName,
			TAB.CustomerNumber,
			TAB.CustomerTaxID,
			TAB.CustomerAddress,
			TAB.CustomerCity,
			TAB.CustomerCountry,
			TAB.CustomerZip,
			Common.GetDateTime2(),
			@ProcessUserID
		FROM @CustomerUpdate TAB
			INNER JOIN #CustomerUpdateValidation CUV ON CUV.SaleExternalId = TAB.SaleExternalId

		INSERT INTO Sale.FiscalRegistrationUpdate(
			SaleID,
			SalePaymentOrder,
			BusinessPremiseId,
			SaleNumber,
			PosNumber,
			SaleClosed,
			RequestStatus,
			ReceiptNumber,
			ExportedReceiptNumber,
			TaxpayerTaxNumber,
			AppointingTaxpayerTaxNumber,
			FiscalIdentificationCode,
			TaxpayerSecurityCode,
			TaxpayerSignatureCode,
			RequestErrorCode,
			RequestErrorMessage,
			Created,
			CreatedBy
		)
		SELECT
			SID.ID,
			SID.PaymentOrder,
			TAB.BusinessPremiseNumber,
			TAB.SaleNumber,
			TAB.PosNumber,
			TAB.SaleClosed,
			TAB.RequestStatus,
			TAB.ReceiptNumberEs,
			TAB.ReceiptNumberEet,
			TAB.TaxNumber,
			TAB.MandatingTaxNumber,
			TAB.FiscalIdentificationCode,
			TAB.TaxpayerSecurityCode,
			TAB.TaxpayerSignatureCode,
			TAB.ErrorCode,
			TAB.ErrorMessage,
			Common.GetDateTime2(),
			@ProcessUserID
		FROM @FiscalRegistrationUpdate TAB
			INNER JOIN @SaleIDs SID ON SID.ExternalId = TAB.SaleExternalId

		INSERT INTO Sale.OptReconciliation(
			PetrolStationID,
			UniCustomerID,
			ExternalId,
			TerminalId,
			TerminalTypeId,
			PosNumber,
			Batch,
			Amount,
			StatusNumber,
			StatusDescription,
			CloseDate,
			OpenDate,
			[User],
			Created,
			CreatedBy
		)
		SELECT
			TAB.PetrolStationID,
			TAB.UniCustomerID,
			TAB.ExternalId,
			TAB.TerminalId,
			TAB.TerminalTypeId,
			TAB.PosNumber,
			TAB.Batch,
			TAB.Amount,
			TAB.StatusNumber,
			TAB.StatusDescription,
			TAB.CloseDate,
			TAB.OpenDate,
			TAB.[User],
			Common.GetDateTime2(),
			@ProcessUserID
		FROM @OptReconciliation TAB

		INSERT INTO Sale.OptBanknote(
			OptReconciliationID,
			CurrencyID,
			NominalValue,
			[Count],
			Amount,
			DamagedCount,
			Created,
			CreatedBy
		)
		SELECT
			OPTR.ID,
			TAB.CurrencyID,
			TAB.NominalValue,
			TAB.[Count],
			TAB.Amount,
			TAB.DamagedCount,
			Common.GetDateTime2(),
			@ProcessUserID
		FROM @OptBanknote TAB
			LEFT OUTER JOIN Sale.OptReconciliation OPTR ON OPTR.PetrolStationID = TAB.PetrolStationID
				AND OPTR.ExternalId = TAB.ExternalId
				AND OPTR.TerminalId = TAB.TerminalId
				AND OPTR.TerminalTypeId = TAB.TerminalTypeId
				AND OPTR.PosNumber = TAB.PosNumber

		IF (@DialogSequenceNumber <> 9999)
		BEGIN
			INSERT INTO SapTransfer.SaleDialogSequenceLog (
				PetrolStationID,
				SequenceNumber,
				DateTime,
				Created
			)
			SELECT
				@PetrolStationID,
				@DialogSequenceNumber,
				@DialogDateTime,
				Common.GetDateTime2()
		END
		ELSE
		BEGIN
			DELETE FROM SapTransfer.SaleDialogSequenceLog WHERE PetrolStationID = @PetrolStationID
		END

		-- Odeslani dialogu do SAPu
		DECLARE @Content nvarchar(MAX) = CAST(@ContentXml AS nvarchar(MAX))

		DECLARE @PetrolStationSapCode varchar(10),
				@PetrolStationNumber varchar(4),
				@DomainID tinyint,
				@FileName nvarchar(50),
				@ExportFileID int,
				@RowCount int,
				@Cycle int

		IF OBJECT_ID('tempdb..#PartnerMapping') IS NOT NULL
			DROP TABLE #PartnerMapping;

		CREATE TABLE #PartnerMapping (
			RowNumber int,
			IdentificationNumber varchar(15),
			SapCode varchar(10)
		)

		IF OBJECT_ID('tempdb..#VatMapping') IS NOT NULL
			DROP TABLE #VatMapping;

		CREATE TABLE #VatMapping (
			RowNumber int,
			Rate decimal(5,2),
			SapCode char(2)
		)

		IF OBJECT_ID('tempdb..#OwnerMapping') IS NOT NULL
			DROP TABLE #OwnerMapping;

		CREATE TABLE #OwnerMapping (
			RowNumber int,
			Number int,
			SapCode varchar(10)
		)

		INSERT INTO #PartnerMapping (
			RowNumber,
			IdentificationNumber,
			SapCode
		)
		SELECT
			ROW_NUMBER() OVER(ORDER BY P.ID ASC),
			P.IdentificationNumber,
			P.SapCode
		FROM PetrolStation.Partner P
			INNER JOIN #Sale S ON S.PartnerIdentificationNumber = P.IdentificationNumber

		INSERT INTO #VatMapping (
			RowNumber,
			Rate,
			SapCode
		)
		SELECT
			ROW_NUMBER() OVER(ORDER BY VS.VatTypeID ASC),
			V.Rate,
			VS.SapCode
		FROM SapTransfer.VatTypeSapCode VS
			INNER JOIN Vat.Vat V ON V.VatTypeID = VS.VatTypeID
			INNER JOIN #SaleItem SI ON SI.VatRate = V.Rate
				AND V.IsActive = 1
		WHERE VS.UniCustomerID = @UniCustomerID

		INSERT INTO #OwnerMapping (
			RowNumber,
			Number,
			SapCode
		)
		SELECT
			ROW_NUMBER() OVER(ORDER BY S.Number ASC),
			S.Number,
			S.SapCode
		FROM Supply.Supplier S
			INNER JOIN #SaleItem SI ON SI.AgencySupplierNumber = S.Number
		WHERE IsCentral = 1
			OR PetrolStationID = @PetrolStationID

		SELECT @DomainID = ID
		FROM Scheduler.Domain
		WHERE Acronym = 'EXPORT_SAP_INBOUND'

		SELECT @FileName = [FileName]
		FROM Import.ImportedBatch
		WHERE ID = @ImportedBatchID

		SELECT
			@PetrolStationSapCode = SapExternalId,
			@PetrolStationNumber = Export.GetRightAlignedStringWithZero(Number,  3)		-- z ES bude chodit CS na 3 znaky
		FROM PetrolStation.PetrolStation
		WHERE ID = @PetrolStationID

		DECLARE @RemappingGoodsIDFrom varchar(6),
				@RemappingGoodsIDTo varchar(6)

		SET @RemappingGoodsIDFrom = '000000'
		SET @RemappingGoodsIDTo = '999999'

		SET @Content = REPLACE(@Content, 'GoodsID="' + @RemappingGoodsIDFrom + '"', 'GoodsID="' + @RemappingGoodsIDTo + '"')

		SET @Content = REPLACE(@Content, 'PetrolStation="' + CAST(@PetrolStationNumber AS varchar(4)) + '"', 'PetrolStation="' + @PetrolStationSapCode + '"')

		SET @Cycle = 1
		SELECT @RowCount = COUNT(*)
		FROM #PartnerMapping

		WHILE (@RowCount >= @Cycle)
		BEGIN
			SELECT @Content = REPLACE(@Content, 'PartnerID="' + CAST(IdentificationNumber AS varchar(15)) + '"', 'PartnerID="' + SapCode + '"')
			FROM #PartnerMapping
			WHERE RowNumber = @Cycle

			SET @Cycle += 1
		END

		SET @Cycle = 1
		SELECT @RowCount = COUNT(*)
		FROM #VatMapping

		WHILE (@RowCount >= @Cycle)
		BEGIN
			SELECT @Content = REPLACE(@Content, 'SaleItemTax="' + CAST(Rate AS varchar(6)) + '"', 'SaleItemTax="' + SapCode + '"')
			FROM #VatMapping
			WHERE RowNumber = @Cycle

			SELECT @Content = REPLACE(@Content, 'CashMoveTax="' + CAST(Rate AS varchar(6)) + '"', 'CashMoveTax="' + SapCode + '"')
			FROM #VatMapping
			WHERE RowNumber = @Cycle

			SET @Cycle += 1
		END

		SET @Cycle = 1
		SELECT @RowCount = COUNT(*)
		FROM #OwnerMapping

		WHILE (@RowCount >= @Cycle)
		BEGIN
			SELECT @Content = REPLACE(@Content, 'SaleItemOwner="' + CAST(Number AS varchar(12)) + '"', 'SaleItemOwner="' + SapCode + '"')
			FROM #OwnerMapping
			WHERE RowNumber = @Cycle

			SELECT @Content = REPLACE(@Content, 'OwnerID="' + CAST(Number AS varchar(12)) + '"', 'OwnerID="' + SapCode + '"')
			FROM #OwnerMapping
			WHERE RowNumber = @Cycle

			SET @Cycle += 1
		END

		IF (@IsFranchise = 1)
		BEGIN
			SET @Cycle = 1
			SELECT @RowCount = COUNT(*)
			FROM #LocalGoodsMapping

			WHILE (@RowCount >= @Cycle)
			BEGIN
				SELECT @Content = REPLACE(@Content, 'GoodsID="' + CAST(GoodsNumber AS varchar(9)) + '"', 'GoodsID="' + @DofoLocalArticleGoodsNumber + '"')
				FROM #LocalGoodsMapping
				WHERE RowNumber = @Cycle

				SET @Cycle += 1
			END
		END

		EXEC Export.SetExportedDataForPetrolStation
			'SAP_INBOUND',
			@DomainID,
			@PetrolStationID,
			NULL,
			NULL,
			@FileName,
			'X',
			@Content,
			NULL,
			0,
			@ProcessUserID,
			@ExportFileID OUTPUT

		INSERT INTO SapTransfer.ProcessedData (
			ExportFileID,
			ImportedBatchID,
			Created
		)
		SELECT
			@ExportFileID,
			@ImportedBatchID,
			Common.GetDateTime2()

		COMMIT TRANSACTION ImportDialogXmlDataSALES_v6_1

		EXEC Logging.InsertSuccessToLog @ModuleID, @ProcessUserID, 'Finished'
	END TRY
	BEGIN CATCH
		SET @ErrorMessage = Logging.FormatErrorMessage()

		IF (@@TRANCOUNT > 0)
			ROLLBACK TRANSACTION ImportDialogXmlDataSALES_v6_1

		-- 1 - DC_UNK (DailyCheck unknown) - nebyl dokoncen predchozi den, stav posledniho DAILYCHECKu je UNKNOWN
		-- 2 - DC_ERR (DailyCheck error) - nebyl dokoncen predchozi den, stav posledniho DAILYCHECKu je ERROR
		-- 3 - UNP_DIA (Unprocessed dialog) - Suspendace CS na zaklade chyby pri zpracovani dialogu SALES. Vsechny ostatni chyby uz byly zapsany
		-- 4 - MIS_DIA (Missing dialog) - Kontrola na poradi dialogu
		IF (NOT EXISTS(SELECT 1 FROM SapTransfer.SuspendedPetrolStation WHERE PetrolStationID = @PetrolStationID AND ImportDialogID = 'SALES'))
		BEGIN
			INSERT INTO SapTransfer.SuspendedPetrolStation (
					PetrolStationID,
					ImportDialogID,
					ImportedBatchID,
					SapTransferErrorTypeID,
					Created
				)
			SELECT
				@PetrolStationID,
				'SALES',
				@ImportedBatchID,
				ISNULL(@SapTransferErrorTypeID, 3),
				Common.GetDateTime2()
		END

		--Odeslat notifikaci
		SELECT @PSNumber = Export.GetRightAlignedStringWithZero(Number, 3)
		FROM PetrolStation.PetrolStation
		WHERE ID = @PetrolStationID

		SET @ToEmails = Security.GetSettingsValue('SapTransfer.NotificationBenzina.Email')
		SET @ToCcEmails = Security.GetSettingsValue('SapTransfer.NotificationUnicode.Email')

		SET @Subject = N'SAP SALES Transfer error'

		SET @Body = N'Dialogs SALES processing and transfer from WO to SAP has been stopped for PetrolStation: ' + @PSNumber + N' (' + ISNULL(@ValidationMessage, @ErrorMessage) +  N').'

		EXEC Message.CreateEmail @ToEmails, @ToCcEmails, @ToBccEmails, NULL, @Subject, @Body, @ProcessUserID

		IF (@Handle IS NOT NULL)
		BEGIN
			EXEC sp_xml_removedocument @Handle
		END

		EXEC Logging.InsertErrorToLog @ModuleID, @ProcessUserID, @ErrorMessage, @ContentXml

		RAISERROR(@ErrorMessage, 16, 1)
	END CATCH

	RETURN 0
END
