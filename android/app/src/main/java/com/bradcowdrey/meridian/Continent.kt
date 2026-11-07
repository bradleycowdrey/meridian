package com.bradcowdrey.meridian

/**
 * The continent a card's city is on, from its country (GeoNames' country to continent table), for the
 * automatic continent groups ("Europe", "Asia"). Russia is Asia east of the Urals (an "Asia/" time
 * zone), else Europe. No country (UTC, fixed offsets) has no continent.
 */
object Continent {
    /** The continents in the order the groups show. */
    val ordered: List<String> = listOf("North America", "South America", "Europe", "Africa", "Asia", "Oceania", "Antarctica")

    private val names = mapOf(
        "NA" to "North America", "SA" to "South America", "EU" to "Europe", "AF" to "Africa",
        "AS" to "Asia", "OC" to "Oceania", "AN" to "Antarctica",
    )

    private const val TABLE = "ADEU;AEAS;AFAS;AGNA;AINA;ALEU;AMAS;ANNA;AOAF;AQAN;ARSA;ASOC;ATEU;AUOC;AWNA;AXEU;AZAS;BAEU;BBNA;BDAS;BEEU;BFAF;BGEU;BHAS;BIAF;BJAF;BLNA;BMNA;BNAS;BOSA;BQNA;BRSA;BSNA;BTAS;BVAN;BWAF;BYEU;BZNA;CANA;CCAS;CDAF;CFAF;CGAF;CHEU;CIAF;CKOC;CLSA;CMAF;CNAS;COSA;CRNA;CSEU;CUNA;CVAF;CWNA;CXOC;CYEU;CZEU;DEEU;DJAF;DKEU;DMNA;DONA;DZAF;ECSA;EEEU;EGAF;EHAF;ERAF;ESEU;ETAF;FIEU;FJOC;FKSA;FMOC;FOEU;FREU;GAAF;GBEU;GDNA;GEAS;GFSA;GGEU;GHAF;GIEU;GLNA;GMAF;GNAF;GPNA;GQAF;GREU;GSAN;GTNA;GUOC;GWAF;GYSA;HKAS;HMAN;HNNA;HREU;HTNA;HUEU;IDAS;IEEU;ILAS;IMEU;INAS;IOAS;IQAS;IRAS;ISEU;ITEU;JEEU;JMNA;JOAS;JPAS;KEAF;KGAS;KHAS;KIOC;KMAF;KNNA;KPAS;KRAS;KWAS;KYNA;KZAS;LAAS;LBAS;LCNA;LIEU;LKAS;LRAF;LSAF;LTEU;LUEU;LVEU;LYAF;MAAF;MCEU;MDEU;MEEU;MFNA;MGAF;MHOC;MKEU;MLAF;MMAS;MNAS;MOAS;MPOC;MQNA;MRAF;MSNA;MTEU;MUAF;MVAS;MWAF;MXNA;MYAS;MZAF;NAAF;NCOC;NEAF;NFOC;NGAF;NINA;NLEU;NOEU;NPAS;NROC;NUOC;NZOC;OMAS;PANA;PESA;PFOC;PGOC;PHAS;PKAS;PLEU;PMNA;PNOC;PRNA;PSAS;PTEU;PWOC;PYSA;QAAS;REAF;ROEU;RSEU;RUEU;RWAF;SAAS;SBOC;SCAF;SDAF;SEEU;SGAS;SHAF;SIEU;SJEU;SKEU;SLAF;SMEU;SNAF;SOAF;SRSA;SSAF;STAF;SVNA;SXNA;SYAS;SZAF;TCNA;TDAF;TFAN;TGAF;THAS;TJAS;TKOC;TLOC;TMAS;TNAF;TOOC;TRAS;TTNA;TVOC;TWAS;TZAF;UAEU;UGAF;UMOC;USNA;UYSA;UZAS;VAEU;VCNA;VESA;VGNA;VINA;VNAS;VUOC;WFOC;WSOC;XKEU;YEAS;YTAF;ZAAF;ZMAF;ZWAF"

    /** Country code -> continent name. */
    private val byCountry: Map<String, String> by lazy {
        TABLE.split(';').filter { it.length == 4 }.mapNotNull { e -> names[e.substring(2)]?.let { e.substring(0, 2) to it } }.toMap()
    }

    /** The continent of a country ("GB" -> "Europe"); Russia by its time zone. */
    fun of(country: String?, zoneId: String): String? {
        val cc = country?.uppercase() ?: return null
        if (cc == "RU") return if (zoneId.startsWith("Asia/")) "Asia" else "Europe"
        return byCountry[cc]
    }

    /** The card's continent, from its country. */
    fun of(place: Place): String? = of(place.country, place.zoneId)
}
