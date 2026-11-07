import Foundation

/// The continent a city is on ("Europe"), for the automatic continent groups.
enum Continent {
    /// Settings: group cities by continent automatically (on unless turned off).
    static var autoGroups: Bool {
        get { UserDefaults.standard.object(forKey: "continentGroups") as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: "continentGroups") }
    }

    /// Continent names, in the order the groups show.
    static let ordered = ["North America", "South America", "Europe", "Africa", "Asia", "Oceania", "Antarctica"]

    /// The continent a card's city is on, or nil (UTC and fixed offsets have no country).
    static func name(for place: Place) -> String? {
        guard let cc = place.country?.uppercased(), let code = byCountry[cc] else { return nil }
        // Russia spans two continents: its time zone says which.
        if cc == "RU" { return place.timeZoneID.hasPrefix("Asia/") ? "Asia" : "Europe" }
        return names[code]
    }

    private static let names = ["NA": "North America", "SA": "South America", "EU": "Europe", "AF": "Africa",
                                "AS": "Asia", "OC": "Oceania", "AN": "Antarctica"]

    /// Country code → continent code (GeoNames).
    private static let byCountry: [String: String] = {
        let table = "ADEU;AEAS;AFAS;AGNA;AINA;ALEU;AMAS;ANNA;AOAF;AQAN;ARSA;ASOC;ATEU;AUOC;AWNA;AXEU;AZAS;BAEU;BBNA;BDAS;BEEU;BFAF;BGEU;BHAS;BIAF;BJAF;BLNA;BMNA;BNAS;BOSA;BQNA;BRSA;BSNA;BTAS;BVAN;BWAF;BYEU;BZNA;CANA;CCAS;CDAF;CFAF;CGAF;CHEU;CIAF;CKOC;CLSA;CMAF;CNAS;COSA;CRNA;CSEU;CUNA;CVAF;CWNA;CXOC;CYEU;CZEU;DEEU;DJAF;DKEU;DMNA;DONA;DZAF;ECSA;EEEU;EGAF;EHAF;ERAF;ESEU;ETAF;FIEU;FJOC;FKSA;FMOC;FOEU;FREU;GAAF;GBEU;GDNA;GEAS;GFSA;GGEU;GHAF;GIEU;GLNA;GMAF;GNAF;GPNA;GQAF;GREU;GSAN;GTNA;GUOC;GWAF;GYSA;HKAS;HMAN;HNNA;HREU;HTNA;HUEU;IDAS;IEEU;ILAS;IMEU;INAS;IOAS;IQAS;IRAS;ISEU;ITEU;JEEU;JMNA;JOAS;JPAS;KEAF;KGAS;KHAS;KIOC;KMAF;KNNA;KPAS;KRAS;KWAS;KYNA;KZAS;LAAS;LBAS;LCNA;LIEU;LKAS;LRAF;LSAF;LTEU;LUEU;LVEU;LYAF;MAAF;MCEU;MDEU;MEEU;MFNA;MGAF;MHOC;MKEU;MLAF;MMAS;MNAS;MOAS;MPOC;MQNA;MRAF;MSNA;MTEU;MUAF;MVAS;MWAF;MXNA;MYAS;MZAF;NAAF;NCOC;NEAF;NFOC;NGAF;NINA;NLEU;NOEU;NPAS;NROC;NUOC;NZOC;OMAS;PANA;PESA;PFOC;PGOC;PHAS;PKAS;PLEU;PMNA;PNOC;PRNA;PSAS;PTEU;PWOC;PYSA;QAAS;REAF;ROEU;RSEU;RUEU;RWAF;SAAS;SBOC;SCAF;SDAF;SEEU;SGAS;SHAF;SIEU;SJEU;SKEU;SLAF;SMEU;SNAF;SOAF;SRSA;SSAF;STAF;SVNA;SXNA;SYAS;SZAF;TCNA;TDAF;TFAN;TGAF;THAS;TJAS;TKOC;TLOC;TMAS;TNAF;TOOC;TRAS;TTNA;TVOC;TWAS;TZAF;UAEU;UGAF;UMOC;USNA;UYSA;UZAS;VAEU;VCNA;VESA;VGNA;VINA;VNAS;VUOC;WFOC;WSOC;XKEU;YEAS;YTAF;ZAAF;ZMAF;ZWAF"
        var map: [String: String] = [:]
        for entry in table.split(separator: ";") where entry.count == 4 {
            map[String(entry.prefix(2))] = String(entry.suffix(2))
        }
        return map
    }()
}
