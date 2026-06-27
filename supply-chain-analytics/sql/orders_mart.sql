/*date: 29.05.2026
name: dim_orders
changelog:
*/

--справочная таблица с заказами
WITH unified_deliveries AS (
    -- Поступление товаров
    SELECT 
        mirKlyuchStrokiZakazaPostavshchikuGuid_PostuplenieTovarovNaSkladTovary as delivery_key,
        Data_PostuplenieTovarovNaSklad as delivery_date,
        Kolichestvo_PostuplenieTovarovNaSkladTovary as qty_received
    FROM D2D_S2P.Purchase_PostuplenieTovarovNaSklad
    
    UNION ALL
    -- Поступление услуг
    SELECT 
        mirKlyuchStrokiZakazaPostavshchikuGuid_PostuplenieUslugVPodrazdelenieUslugi as delivery_key,
        Data_PostuplenieUslugVPodrazdelenie as delivery_date,
        Kolichestvo_PostuplenieUslugVPodrazdelenieUslugi as qty_received
    FROM D2D_S2P.Purchase_PostuplenieUslugVPodrazdelenie
    WHERE Kolichestvo_PostuplenieUslugVPodrazdelenieUslugi > 0
),

deliveries_agg AS (
    SELECT 
        delivery_key,
        SUM(qty_received) as total_received_qty,
        MAX(delivery_date) as last_delivery_date
    FROM (
        SELECT 
            delivery_key,
            delivery_date,
            MAX(qty_received) as qty_received
        FROM unified_deliveries
        GROUP BY delivery_key, delivery_date
    )
    GROUP BY delivery_key
),

base_pos AS (
    SELECT DISTINCT
        pzp.mirKlyuchStrokiZakazaPostavshchikuGuid_ZakazPostavshchikuTovary as mirKlyuchStrokiZakazaPostavshchikuGuid_ZakazPostavshchikuTovary,
        pzp.NomenklaturaGuid_ZakazPostavshchikuTovary as nom_guid,
        
        -- geounit (по префиксам номера заказа)
        CASE 
            WHEN LEFT(pzp.mirNomer_ZakazPostavshchiku, 3) IN ('RAH', 'RMM') THEN 'ASG'
            WHEN LEFT(pzp.mirNomer_ZakazPostavshchiku, 3) = 'RSH' THEN 'SKG'
            WHEN LEFT(pzp.mirNomer_ZakazPostavshchiku, 3) IN ('RKY', 'RMS', 'RNU', 'RNY', 'RSM', 'RTB', 'RUS', 'RVK') THEN 'RUL'
            ELSE 'OTHER'
        END as po_geounit,
        
        toDate(coalesce(pzp.mirDataSoglasovaniyaDO_ZakazPostavshchiku, pzp.Data_ZakazPostavshchiku)) as po_date,
        pzp.mirNomer_ZakazPostavshchiku as po_number,
        
        CASE 
            WHEN pzp.mirNomerDokumentaIstoricheskiy_ZakazPostavshchiku IS NOT NULL 
                 AND pzp.mirNomerDokumentaIstoricheskiy_ZakazPostavshchiku != ''
            THEN pzp.mirNomerDokumentaIstoricheskiy_ZakazPostavshchiku
            ELSE pzp.mirNomer_ZakazPostavshchiku
        END as po_number_swps,
        
        pzp.Kontragent_ZakazPostavshchiku as po_supplier,
        pzp.KontragentMDM_Key as po_supplier_mdm,
        pk.supplier_country as supplier_country,
        pk.party_type as party_type,
        pk.supplier_tax_id as supplier_tax_id, 
        pk.supplier_sm_level as supplier_sm_level,
        ROUND(pzp.TSena_ZakazPostavshchikuTovary, 2) as po_unit_price,
        pzp.Kolichestvo_ZakazPostavshchikuTovary as po_qty,
        ROUND(pzp.Summa_ZakazPostavshchikuTovary, 2) as po_total,
        
        ROUND(COALESCE(da.total_received_qty, 0) * pzp.TSena_ZakazPostavshchikuTovary, 2) as po_total_received,
        
        pzp.mirSummaVValyuteSLB_ZakazPostavshchiku as po_total_sum_usd,
        pzp.Valyuta_ZakazPostavshchiku as po_currency,
        
        -- Курс USD
        CASE 
            WHEN pzp.Valyuta_ZakazPostavshchiku = 'RUB' 
                 AND pzp.mirKursSLB_ZakazPostavshchiku IS NOT NULL
            THEN CAST(pzp.mirKursSLB_ZakazPostavshchiku AS Decimal(15, 2))
            WHEN pzp.mirSummaVValyuteSLB_ZakazPostavshchiku IS NOT NULL 
                 AND pzp.mirSummaVValyuteSLB_ZakazPostavshchiku != 0
                 AND pzp.SummaDokumenta_ZakazPostavshchiku IS NOT NULL
            THEN CAST(pzp.SummaDokumenta_ZakazPostavshchiku AS Decimal(15, 2)) / 
                 CAST(pzp.mirSummaVValyuteSLB_ZakazPostavshchiku AS Decimal(15, 2))
            ELSE NULL
        END as po_rate_usd,
        
        COALESCE(da.total_received_qty, 0) as po_qty_received,
        da.last_delivery_date as gr_date,
        
        coalesce(coalesce(pzp.mirDataETA_ZakazPostavshchikuTovary, pzp.mirDatacSPD_ZakazPostavshchikuTovary), 
                pzp.DataPervogoPostupleniya_ZakazPostavshchiku) as estimated_delivery_date,
        
        CASE 
            WHEN COALESCE(da.total_received_qty, 0) >= pzp.Kolichestvo_ZakazPostavshchikuTovary THEN 'closed'
            WHEN COALESCE(da.total_received_qty, 0) > 0 THEN 'partial'
            ELSE 'open'
        END as po_status,
        
        pzp.Status_ZakazPostavshchiku as po_status_mir,
        
        CASE
            WHEN pzp.mirDataSoglasovaniyaDO_ZakazPostavshchiku IS NOT NULL 
                 OR pzp.Status_ZakazPostavshchiku IN ('Подтвержден', 'Согласован', 'Отправлен поставщику (мир)', 'Закрыт')
            THEN 'true'
            ELSE 'false'
        END as po_approval,
        
        pznz.Katalog_mirZayavkaNaZakupkuTovaryIUslugi as po_from_catalog,
        pzp.mirFinansovayaObrabotka_ZakazPostavshchikuTovary as po_finance_processing
        
    FROM D2D_S2P.Purchase_ZakazPostavshchiku pzp
    LEFT JOIN (SELECT 
                    SsylkaGuid_Kontragenty, 
                    StranaRegistratsii_Kontragenty as supplier_country, 
                    CASE 
                        WHEN mirInterkampani_Kontragenty LIKE '%ICO%' THEN 'ICO'
                        WHEN mirInterkampani_Kontragenty LIKE '%3rd%' THEN '3rd_party'
                        ELSE 'unknown'
                    END as party_type,
                    CASE 
                        WHEN StranaRegistratsii_Kontragenty = 'РОССИЯ' 
                        THEN INN_Kontragenty
                        ELSE NalogovyyNomer_Kontragenty
                    END as supplier_tax_id, 
                    max(mirSMUroven_Kontragenty) as supplier_sm_level
                FROM D2D_S2P.Purchase_Kontragenty 
                GROUP BY 1,2,3,4) pk
        ON pzp.KontragentGuid_ZakazPostavshchiku = pk.SsylkaGuid_Kontragenty
    LEFT JOIN D2D_S2P.Purchase_mirZayavkaNaZakupku pznz 
        ON pzp.mirPotrebnostGuid_ZakazPostavshchikuTovary = pznz.KlyuchStrokiGuid_mirZayavkaNaZakupkuTovaryIUslugi
        AND pzp.NomenklaturaGuid_ZakazPostavshchikuTovary = pznz.NomenklaturaGuid_mirZayavkaNaZakupkuTovaryIUslugi
        AND pznz.Proveden_mirZayavkaNaZakupku = True
    LEFT JOIN deliveries_agg da 
        ON pzp.mirKlyuchStrokiZakazaPostavshchikuGuid_ZakazPostavshchikuTovary = da.delivery_key
    WHERE pzp.PometkaUdaleniya_ZakazPostavshchiku = 'False' 
        AND pzp.Otmeneno_ZakazPostavshchikuTovary = 'False'
),

dim_orders AS (
    SELECT 
        base_pos.mirKlyuchStrokiZakazaPostavshchikuGuid_ZakazPostavshchikuTovary,
        base_pos.nom_guid,
        base_pos.po_geounit,
        base_pos.po_date,
        base_pos.po_number,
        base_pos.po_number_swps,
        base_pos.po_supplier,
        base_pos.po_supplier_mdm,
        base_pos.supplier_country,
        base_pos.party_type,
        base_pos.supplier_tax_id, 
        base_pos.supplier_sm_level,
        base_pos.po_unit_price,
        base_pos.po_qty,
        base_pos.po_qty_received,
        base_pos.po_qty - base_pos.po_qty_received as po_qty_remaining,
        base_pos.po_total,
        base_pos.po_total_received,
        base_pos.po_total_sum_usd,
        base_pos.po_currency,
        base_pos.po_rate_usd,
        base_pos.po_status,
        base_pos.po_status_mir,
        base_pos.po_approval,
        base_pos.po_from_catalog,
        base_pos.po_finance_processing,
        
        -- po_unit_price_usd для всех валют
        CASE 
            WHEN base_pos.po_currency = 'USD' THEN base_pos.po_unit_price
            WHEN base_pos.po_rate_usd IS NOT NULL THEN ROUND(base_pos.po_unit_price / NULLIF(base_pos.po_rate_usd, 0), 4)
            ELSE NULL
        END as po_unit_price_usd,
        
        -- po_delivery_date по старой логике
        CASE 
            WHEN base_pos.po_status = 'closed' THEN toDate(base_pos.gr_date)
            ELSE toDate(base_pos.estimated_delivery_date)
        END as po_delivery_date,
        
        -- Просрочка в днях
        CASE 
            WHEN base_pos.po_status IN ('open', 'partial')
                AND base_pos.estimated_delivery_date < today()
            THEN DATEDIFF('day', base_pos.estimated_delivery_date, today())
            ELSE 0
        END as po_delivery_delay_days,
        
        -- po_total_usd для всех валют
        CASE 
            WHEN base_pos.po_currency = 'USD' THEN base_pos.po_total
            WHEN base_pos.po_rate_usd IS NOT NULL THEN ROUND(base_pos.po_total / NULLIF(base_pos.po_rate_usd, 0), 2)
            ELSE NULL
        END as po_total_usd,
        
        -- po_total_usd_received для всех валют
        CASE 
            WHEN base_pos.po_currency = 'USD' THEN ROUND(base_pos.po_unit_price * base_pos.po_qty_received, 2)
            WHEN base_pos.po_rate_usd IS NOT NULL THEN ROUND((base_pos.po_unit_price / NULLIF(base_pos.po_rate_usd, 0)) * base_pos.po_qty_received, 2)
            ELSE NULL
        END as po_total_usd_received
        
    FROM base_pos
)

SELECT 
    *,
    toTimeZone(now(), 'UTC') AS "D2D Refreshed (UTC)"
FROM dim_orders
WHERE po_number NOT LIKE '%/%'
ORDER BY mirKlyuchStrokiZakazaPostavshchikuGuid_ZakazPostavshchikuTovary
