# Hand corrections for scripts/metros.py, from the metro audit of November 2026 (checked against OMB MSAs, StatCan CMAs, Eurostat FUAs, INEGI, IBGE and census urban agglomerations).
# Selectors: (name, cc), (name, cc, "State prefix") or (name, cc, latitude); each must match exactly one row of Resources/Data/cities.tsv.
CC_BY_ZONE={'Asia/Macau':'MO'}
COORD={('Masan','KR'):(35.20,128.57),('Modakeke','NG'):(7.47,4.56),('Kouandé','BJ'):(10.33,1.69)}
POP={
 # stale / undercounted principal cities (official figures)
 ('Ulan Bator','MN'):1_650_000, ('Ahvaz','IR'):1_184_788, ('Freetown','SL'):1_055_964,
 ('Bishkek','KG'):1_150_000, ('Dushanbe','TJ'):1_200_000,
 # rows carrying district/prefecture/county/tehsil populations -> urban figure
 ('Wuzhong','CN'):400_000, ('Lüliang','CN'):400_000, ('Bazhong','CN'):500_000, ('Qingyang','CN',35.71):400_000,
 ('Bayan Nur','CN'):500_000, ('Zhongwei','CN'):400_000, ('Wuwei','CN',37.93):500_000, ('Ordos','CN'):700_000,
 ('Guankou','CN'):400_000, ('Heshan','CN',28.57):700_000, ('Yunfu','CN'):400_000, ('Laiwu','CN'):600_000,
 ('Kakamega','KE'):107_000, ('Kallakurichi','IN'):60_000, ('Nowrangapur','IN'):30_000, ('Tirunelveli','IN'):500_000,
 ('Jepara','ID'):100_000, ('Bannu','PK'):150_000, ('Arifwala','PK'):120_000, ('Chunian','PK'):100_000,
 ('Dera Ismail Khan','PK'):250_000, ('Muzaffarābād','PK'):150_000, ('Dhirkot','PK'):30_000,
 ('Efon-Alaaye','NG'):60_000,
}
ZERO=[ # duplicate / district rows already counted in a parent row (kept as members, count 0, never a core)
 ('Sainte-Foy','CA'),('La Cité-Limoilou','CA'),('La Haute-Saint-Charles','CA'),('Charlesbourg','CA'),('Beauport','CA'),
 ('Les Rivières','CA'),('Neufchâtel-Est–Lebourgneuf','CA'),('Stoney Creek','CA'),('Ancaster','CA'),('Waterdown','CA'),

 ('Pravyi Bereh','UA'),('Tsentralnyi','UA',47.10),('Livoberezhnyi','UA',47.10),('Kalmiuskyi','UA'),('Prymorskyi','UA',47.08),
 ('Verhunskyi','UA'),('Vilkhivskyi','UA'),('Skhidni Kvartaly','UA'),('Shevchenkivskyi','UA',48.57),('Kamyanobridskyi','UA'),
 ('Mansilingan','PH'),('Budta','PH'),('Malingao','PH'),
 ('Minato','JP',34.22),('Katsuta','JP'),('Zhu Cheng City','CN'),('Lianshan','CN',40.76),('Dawukou','CN'),('Lizhi','CN'),
 ('Shenglilu','CN'),('Nandajie','CN'),('Puyang','CN',29.46),
 ('North Stamford','US'),('East Norwalk','US'),('City of Milford (balance)','US'),('North Chicopee','US'),
 ('Kota Kuala Muda','MY'),('New South Memphis','US'),('Kanayannur','IN'),('Rasapūdipalem','IN'),('Teni','IN'),
 ('Ramagundam','IN'),('Gorakhpur','IN',29.45),('Al Mawşil al Jadīdah','IQ'),('Al Başrah al Qadīmah','IQ'),
 ('East Jerusalem','PS'),('Old City','PS'),('West Jerusalem','IL'),
 ('Santo António','MO'),('Nossa Senhora de Fátima','MO'),('São Lourenço','MO'),('São Lázaro','MO'),('Sé','MO'),('Taipa','MO'),('Luhuan','MO'),('Zhuojiacun','MO'),('Lai Chi Van','MO'),('Dongsheng','CN',39.82),
]
FIX={
 ('Suginami','JP'):'tokyo',('Shinagawa','JP'):'tokyo',('Kotō','JP'):'tokyo',
 # ---- US: outer MSA towns (per-town, because clusters mix MSAs)
 ('Homestead','US'):'miami', ('Valencia','US','California'):'losangeles', ('Castaic','US'):'losangeles',
 ('Rancho Santa Margarita','US'):'losangeles', ('Rosamond','US'):'default',
 ('Temecula','US'):'riverside-us', ('Fallbrook','US'):'sandiego',
 ('Concord','US','California'):'sanfrancisco',('Antioch','US','California'):'sanfrancisco',('Pittsburg','US','California'):'sanfrancisco',
 ('Dublin','US','California'):'sanfrancisco',('Bay Point','US'):'sanfrancisco',('Brentwood','US',37.93):'sanfrancisco',
 ('Oakley','US','California'):'sanfrancisco',('Novato','US'):'sanfrancisco',('Fremont','US','California'):'sanfrancisco',
 ('Newark','US','California'):'sanfrancisco',('Livermore','US'):'sanfrancisco',('Pleasanton','US'):'sanfrancisco',
 ('Gilroy','US'):'sanjose-us',
 ('Ashburn','US','Virginia'):'washingtondc',('Manassas','US'):'washingtondc',('Linton Hall','US'):'washingtondc',('Sudley','US'):'washingtondc',
 ('Leesburg','US','Virginia'):'washingtondc',('Frederick','US','Maryland'):'washingtondc',('Ballenger Creek','US'):'washingtondc',
 ('Damascus','US','Maryland'):'washingtondc',('Fredericksburg','US','Virginia'):'washingtondc',
 ('Severn','US'):'baltimore-us',('Odenton','US'):'baltimore-us',('Westminster','US','Maryland'):'baltimore-us',
 ('Wilmington','US','Delaware'):'philadelphia',('Newark','US','Delaware'):'philadelphia',('Middletown','US','Delaware'):'philadelphia',
 ('Bear','US','Delaware'):'philadelphia',('Elkton','US','Maryland'):'philadelphia',('Pottstown','US'):'philadelphia',('Limerick','US'):'philadelphia',
 ('Haverhill','US','Massachusetts'):'boston',('Methuen','US'):'boston',('Salem','US','New Hampshire'):'boston',
 ('Derry Village','US'):'boston',('Derry','US','New Hampshire'):'boston',('Dover','US','New Hampshire'):'boston',('Portsmouth','US','New Hampshire'):'boston',
 ('Castle Rock','US','Colorado'):'denver',('Kenosha','US'):'chicago',('Pleasant Prairie','US'):'chicago',('Zion','US','Illinois'):'chicago',
 ('Round Lake Beach','US'):'chicago',('Grayslake','US'):'chicago',('Libertyville','US'):'chicago',('Round Lake','US'):'chicago',
 ('Crystal Lake','US'):'chicago',('Algonquin','US','Illinois'):'chicago',('Lake in the Hills','US'):'chicago',('McHenry','US','Illinois'):'chicago',
 ('Woodstock','US','Illinois'):'chicago',('Cary','US','Illinois'):'chicago',('Sycamore','US','Illinois'):'chicago',('Yorkville','US','Illinois'):'chicago',
 ('Valparaiso','US','Indiana'):'chicago',
 ('Galveston','US'):'houston',('La Marque','US'):'houston',
 ('San Marcos','US','Texas'):'austin',('New Braunfels','US'):'sanantonio-us',('Seguin','US'):'sanantonio-us',('Canyon Lake','US'):'sanantonio-us',
 ('Murfreesboro','US'):'nashville-us',('Columbia','US',35.62):'nashville-us',('Spring Hill','US','Tennessee'):'nashville-us',('Lebanon','US','Tennessee'):'nashville-us',
 ('Cartersville','US'):'atlanta',('McDonough','US'):'atlanta',('Griffin','US','Georgia'):'atlanta',('Carrollton','US','Georgia'):'atlanta',
 ('Woodstock','US','Georgia'):'atlanta',('Canton','US','Georgia'):'atlanta',('Acworth','US'):'atlanta',
 ('Florence','US','Arizona'):'phoenix',('Eloy','US'):'phoenix',
 ('Waterford','US','Michigan'):'detroit',('Auburn Hills','US'):'detroit',('Weirton','US'):'default',('Weirton Heights','US'):'default',('Weatherford','US','Texas'):'dallas',('Cleburne','US'):'dallas',('Port Huron','US'):'detroit',('Lorain','US'):'cleveland-us',
 ('Lancaster','US','Ohio'):'columbus-us',('Newark','US','Ohio'):'columbus-us',('Marysville','US','Ohio'):'columbus-us',
 ('Anderson','US','Indiana'):'indianapolis-us',('Salisbury','US','North Carolina'):'charlotte-us',('Statesville','US'):'charlotte-us',
 ('Leesburg','US','Florida'):'orlando-us',('New Bedford','US'):'providence-us',('Woonsocket','US'):'providence-us',
 ('West Bend','US'):'milwaukee-us',('Tooele','US'):'saltlakecity',('McMinnville','US','Oregon'):'portland',
 ('Caledon','CA'):'toronto',('Saint-Jérôme','CA'):'montreal',('Mirabel','CA'):'montreal',('Saint-Lazare','CA'):'montreal',
 ('Saint-Jean-sur-Richelieu','CA'):'default',('Cambridge','CA'):'default',('Fiddlesticks','CA'):'default',('Christopher-Champlain','CA'):'default',('Brantford','CA'):'default',
 ('Blue Mountains','AU'):'sydney',('Mandurah','AU'):'perth',('Corio','AU'):'default',('Lara','AU'):'default',
 # ---- Latin America
 ('Novo Hamburgo','BR'):'portoalegre-br',('Campo Bom','BR'):'portoalegre-br',('Sapiranga','BR'):'portoalegre-br',
 ('Estância Velha','BR'):'portoalegre-br',('Dois Irmãos','BR'):'portoalegre-br',('Ivoti','BR'):'portoalegre-br',
 ('Parobé','BR'):'portoalegre-br',('Nova Hartz','BR'):'portoalegre-br',('Portão','BR'):'portoalegre-br',('Montenegro','BR'):'portoalegre-br',
 ('Taquara','BR'):'portoalegre-br',('Igrejinha','BR'):'portoalegre-br',
 ('Jundiaí','BR'):'default',('Várzea Paulista','BR'):'default',('Campo Limpo Paulista','BR'):'default',('Jarinu','BR'):'default',
 ('Cabreúva','BR'):'default',('Atibaia','BR'):'default',('Bom Jesus dos Perdões','BR'):'default',('Nazaré Paulista','BR'):'default',
 ('São Roque','BR'):'sorocaba-br',('Mairinque','BR'):'sorocaba-br',('Araçariguama','BR'):'sorocaba-br',('Salto','BR'):'sorocaba-br',
 ("Santa Bárbara d'Oeste",'BR'):'campinas-br',
 ('Itaguaí','BR'):'riodejaneiro',('Paracambi','BR'):'riodejaneiro',('Rio Bonito','BR'):'riodejaneiro',('Cachoeiras de Macacu','BR'):'riodejaneiro',
 ('Teresópolis','BR'):'default',('Paty do Alferes','BR'):'default',('Miguel Pereira','BR'):'default',
 ('Aracruz','BR'):'default',('Santa Teresa','BR',-19.94):'default',('Guarapari','BR'):'vitoria-br',
 # ---- Europe
 ('Hamm','DE',51.68):'essen-de',('Duisburg','DE'):'essen-de',('Mülheim','DE',51.43):'essen-de',('Rheinhausen','DE'):'essen-de',('Hochfeld','DE'):'essen-de',('Lünen','DE'):'essen-de',('Bergkamen','DE'):'essen-de',('Werne','DE'):'essen-de',('Selm','DE'):'essen-de',
 ('Unna','DE'):'essen-de',('Kamen','DE'):'essen-de',('Holzwickede','DE'):'essen-de',
 ('Utrecht','NL'):'default',('Nieuwegein','NL'):'default',('Zeist','NL'):'default',('Leidsche Rijn','NL'):'default',
 ('Maarssen','NL'):'default',('Woerden','NL'):'default',('IJsselstein','NL'):'default',
 ('Bournemouth','GB'):'default',('Christchurch','GB'):'default',('Ferndown','GB'):'default',
 ('Burnley','GB'):'default',('Blackburn','GB'):'default',('Luzern','CH'):'default',('Schaffhausen','CH'):'default',
 ('Rhyl','GB'):'default',('Portishead','GB'):'bristol-gb',('Clevedon','GB'):'bristol-gb',('Nailsea','GB'):'bristol-gb',('Burnham-on-Sea','GB'):'bristol-gb',('Loughborough','GB'):'default',('Coalville','GB'):'default',('Melton Mowbray','GB'):'default',('Mountsorrel','GB'):'default',('Wuppertal','DE'):'default',('Remscheid','DE'):'default',('Lipa City','PH'):'default',('Tanauan','PH',14.09):'default',('Santo Tomas','PH',14.11):'default',('Malvar','PH'):'default',('Weston-super-Mare','GB'):'bristol-gb',('Prestatyn','GB'):'default',('Lytham St Annes','GB'):'default',
 ('Tarsus','TR'):'mersin-tr',('Manisa','TR'):'default',('Turgutlu','TR'):'default',('Kilis','TR'):'default',
 ('Pazarcık','TR'):'default',('Yalova','TR'):'default',
 # ---- East Asia
 ('Dongguan','CN'):'shenzhen',('Shijie','CN'):'shenzhen',('Zhangjiagang','CN'):'suzhou-cn',('Puning','CN'):'shantou-cn',
 ('Zhubei','TW'):'hsinchu-tw',('Zhudong','TW'):'hsinchu-tw',('Takamatsu','JP'):'default',('Toyohashi','JP'):'default',('Toyokawa','JP'):'default',
 ('Kusatsu','JP',35.02):'kyoto-jp',('Moriyama','JP',35.06):'kyoto-jp',('Rittō','JP'):'kyoto-jp',('Yasu','JP'):'kyoto-jp',('Konan','JP',35.0):'kyoto-jp',
 ('Masan','KR'):'changwon-kr',('Jiangyin','CN'):'wuxi-cn',('Yixing','CN',31.36):'wuxi-cn',
 # ---- South / SE Asia
 ('Eminabad','PK'):'gujranwala-pk',('Kamoke','PK'):'gujranwala-pk',('Palakkad','IN'):'default',
 ('Chāndpur','BD'):'default',('Farīdpur','BD'):'default',('Hải Dương','VN'):'default',('Việt Trì','VN'):'default',
 ('Phủ Lý','VN'):'default',('Hòa Bình','VN'):'default',('Mỹ Tho','VN'):'default',('Hạ Long','VN'):'default',
 ('Mardan','PK'):'default',('Kohat','PK'):'default',
 # ---- Middle East / Africa
 ('Soshanguve','ZA'):'johannesburg',('Mabopane','ZA'):'johannesburg',('Ga-Rankuwa','ZA'):'johannesburg',('Hammanskraal','ZA'):'johannesburg',
 ('Al Maţarīyah','EG'):'default',('Al Manzalah','EG'):'default',('Iseyin','NG'):'default',
 ('Al Fallūjah','IQ'):'default',('Baqubah','IQ'):'default',('Zahlé','LB'):'default',('Sidon','LB'):'default',
 ('Shibīn al Kawm','EG'):'default',('Damanhur','EG'):'default',('Rosetta','EG'):'default',('Kenitra','MA'):'default',('Mehdya','MA'):'default',
}
GROUP={  # explicit membership lists (named metro boundaries that distance cannot infer)
 'santos-br':[('Santos','BR'),('São Vicente','BR'),('Praia Grande','BR'),('Cubatão','BR'),('Guarujá','BR'),('Bertioga','BR'),
              ('Mongaguá','BR'),('Itanhaém','BR'),('Peruíbe','BR')],
 'jerusalem-il':[('Shu‘fāţ','PS'),('Bayt Ḩanīnā','PS'),('Al ‘Ayzarīyah','PS'),('Ar Rām wa Ḑāḩiyat al Barīd','PS'),('Ma‘ale Adummim','PS'),('‘Aţārūt','PS'),
              ('Bethlehem','PS'),('Bayt Jālā','PS'),('Ramallah','PS'),('Al Bīrah','PS',31.91),('Battir','PS')],
 'leeds-gb':[('Huddersfield','GB'),('Halifax','GB'),('Wakefield','GB'),('Dewsbury','GB'),('Batley','GB'),('Castleford','GB'),
             ('Pontefract','GB'),('Ossett','GB'),('Liversedge','GB'),('Lofthouse','GB'),('South Elmsall','GB')],
 'liverpool-gb':[('St Helens','GB'),('Prescot','GB'),('Widnes','GB'),('Runcorn','GB'),('Skelmersdale','GB')],
 'antwerp-be':[('Berchem','BE'),('Wilrijk','BE'),('Hoboken','BE')],
}
PRECORE=[  # claim before built-ins
 dict(sel=('Toluca','MX'),r=30),
 dict(sel=('Cuernavaca','MX'),r=25),
 dict(sel=('Zhuhai','CN',22.28),r=20),
]
SEED=[  # claim after built-ins, before greedy; force=True: photo whatever the total
 *[dict(sel=s,r=r) for s,r in [
   (('Pittsburgh','US'),50),(('Cincinnati','US'),50),(('Louisville','US','Kentucky'),40),(('Richmond','US','Virginia'),40),
   (('Birmingham','US','Alabama'),40),(('Buffalo','US','New York'),40),(('Grand Rapids','US'),40),(('Rochester','US','New York'),40),
   (('Tucson','US'),40),(('Tulsa','US'),40),(('Fresno','US','California'),40),(('Hartford','US'),30),
   (('Toulouse','FR'),40),(('Bordeaux','FR'),40),(('Gothenburg','SE'),40),(('Thessaloníki','GR'),40),(('Zagreb','HR'),40),
   (('Tegucigalpa','HN'),40),(('Mendoza','AR'),40),(('Aguascalientes','MX'),40),(('Saltillo','MX'),40),
   (('Mersin','TR'),40),(('İzmit','TR'),35),(('Kuwait City','KW'),50)]],
 # not forced: must reach 1M on their own; exist so a neighbour cannot swallow them
 *[dict(sel=s,r=r,force=False) for s,r in [
   (('Tainan','TW'),30),(('Wuxi','CN',31.57),30),(('Düsseldorf','DE'),25),(('Nottingham','GB'),30),(('Cardiff','GB'),35),
   (('Sialkot','PK'),30)]],
]
RADIUS={'seattle':60,'sandiego':60,'chicago':62,'phoenix':70,'dallas':70,'atlanta':65,'austin':50,'houston':75,
        'moscow':125,'peshawar-pk':40,'coimbatore-in':40}
MERGE={  # whole cluster of this core row -> key
 ('Irvine','US'):'losangeles',('Coral Springs','US'):'miami',('West Palm Beach','US'):'miami',('Lancaster','US','California'):'losangeles',
 ('Victorville','US'):'riverside-us',('Murrieta','US'):'riverside-us',('Indio','US'):'riverside-us',
 ('Brentwood','US','New York'):'newyork',('Toms River','US'):'newyork',
 ("O'Fallon",'US','Missouri'):'stlouis-us',('Spring Hill','US','Florida'):'tampa-us',('Newport News','US'):'virginiabeach-us',
 ('Calamba','PH'):'manila',
}
for t in ['Coram','Commack','Centereach','Smithtown','Hauppauge','East Northport','Lake Ronkonkoma','Selden','Kings Park','East Setauket','Setauket-East Setauket']:
    FIX[(t,'US')]='newyork'
DENY={'bridgeport-us','springfield-us','quetzaltenango-gt','pereira-co','piura-pe','eindhoven-nl','koriyama-jp','numazu-jp','mito-jp',
      'peicheng-cn','pizhou-cn','pingdu-cn','yongchuan-cn','gunan-cn','fuling-cn','gujangbagh-cn','shizuishan-cn','huludao-cn',
      'beihai-cn','guangan-cn','yuncheng-cn','zhuchengcity-cn','zhucheng-cn',
      'begusarai-in','karnal-in','saharanpur-in','alappuzha-in','vellore-in','erode-in','sahiwal-pk','kediri-id','cabanatuancity-ph',
      'dagupan-ph','sangli-in','alfayyum-eg','osogbo-ng','adoekiti-ng','akure-ng'}
ALIAS={  # empty: the re-centring seeds below give Guadalajara, Vitória, George Town, Kannur, Āsansol and Islamabad their own keys
       }

# Separate MSAs next to a built-in metro: the owner's rule is the MSA, so these keep the default scene.
FIX.update({
 ('Boulder','US','Colorado'):'default', ('Layton','US','Utah'):'default', ('Durham','US','North Carolina'):'default',
 ('Racine','US','Wisconsin'):'default', ('Bremerton','US'):'default', ('Oshawa','CA'):'default', ('Whitby','CA'):'default',
})

# ======== Round-2 audit fixes (November 2026) ========
# ---- data corrections
ZERO += [('Wanxian','CN'),('Masan','KR'),('Chang-hua','TW'),('Gundupālaiyam','IN'),('Balbala','DJ'),('Placilla','CL')]
POP[('Islamabad','PK')] = 1_108_872
# ---- cross-border / named-boundary groups
GROUP['jerusalem-il'] += [('East Jerusalem','PS'),('Old City','PS')]
# ---- PRECORE (claim before built-ins)
PRECORE += [dict(sel=('Kyoto','JP'),r=17), dict(sel=('Kobe','JP'),r=10), dict(sel=('Meerut','IN'),r=20)]
# ---- SEED: forced (separate 1M+ metros the database undercounts)
SEED += [dict(sel=s,r=r) for s,r in [
  (('Şanlıurfa','TR'),25),(('Poznań','PL'),30),(('Leipzig','DE'),40),(('Lille','FR'),40),(('Haifa','IL'),40),
  (('Hsinchu','TW'),30),(('Changwon','KR'),15),(('Bhilai','IN'),18),(('Islamabad','PK'),45),(('Cagayan de Oro','PH'),40),
  (('Valparaíso','CL'),25),(('Concepción','CL'),32)]]
SEED.append(dict(sel=('The Hague','NL'),r=14,key='thehague-nl'))
SEED.append(dict(sel=('Colorado Springs','US'),r=40,key='coloradosprings'))   # needs the metros.py change (built-in block removed)
# ---- SEED: not forced (re-centre a metro on its real city, or keep a neighbour from swallowing it)
SEED += [dict(sel=s,r=r,force=False,key=k) for s,r,k in [
  (('Guadalajara','MX'),40,'guadalajara-mx'),(('Vitória','BR'),30,'vitoria-br'),(('George Town','MY'),40,'georgetown-my'),
  (('Malappuram','IN'),30,'malappuram-in'),(('Kannur','IN'),35,'kannur-in'),(('Āsansol','IN'),19,'asansol-in'),
  (('Shaoxing','CN'),30,'shaoxing-cn'),(('Fushun','CN'),25,'fushun-cn'),(('Jiangmen','CN'),20,'jiangmen-cn'),
  (('Zhuzhou','CN'),30,'zhuzhou-cn')]]
RADIUS.update({'gujranwala-pk':35,'baghdad-iq':35,'aleppo-sy':30,'alexandria-eg':30})
DENY |= {'tiruppur-in','sialkot-pk','murcia-es','alicante-es','southampton-gb','wanzhou-cn','hezhou-cn',
         'kanazawa-jp','naha-jp','kagoshima-jp','himeji-jp','shizuoka-jp','jeonju-kr',
         'puducherry-in','moradabad-in','gujrat-pk','sukkur-pk','rangpur-bd','rajshahi-bd','hue-vn','thanhhoa-vn','vinh-vn',
         'andijon-uz','namangan-uz','naypyitaw-mm'}

# ---- US (OMB MSAs, 2023 delineation; CT by planning region)
FIX.update({
 # separate small MSAs next to a big one -> default
 ('Bountiful','US'):'default',('Kaysville','US'):'default',('Farmington','US','Utah'):'default',('Centerville','US','Utah'):'default',
 ('Syracuse','US','Utah'):'default',('North Salt Lake','US'):'default',('Highland','US','Utah'):'default',
 ('Lafayette','US','Colorado'):'default',('Louisville','US','Colorado'):'default',('Erie','US','Colorado'):'default',
 ('Mount Pleasant','US','Wisconsin'):'default',('Caledonia','US','Wisconsin'):'default',
 ('Silverdale','US'):'default',('Bainbridge Island','US'):'default',
 ('Vallejo','US'):'default',('Benicia','US'):'default',('Dixon','US','California'):'default',
 ('Stamford','US','Connecticut'):'default',('Meriden','US','Connecticut'):'default',('Bristol','US','Connecticut'):'default',
 ('Killingly Center','US'):'default',('Madera','US','California'):'default',('DeBary','US'):'default',
 ('Twinsburg','US'):'default',('Hudson','US','Ohio'):'default',('Aurora','US','Ohio'):'default',
 ('Rochester','US','Minnesota'):'default',('Richmond','US','Indiana'):'default',
 # wrong big metro
 ('East Palo Alto','US'):'sanfrancisco',('Menlo Park','US'):'sanfrancisco',
 ('Easton','US','Massachusetts'):'providence-us',('Mansfield','US','Massachusetts'):'providence-us',
 ('Crofton','US'):'baltimore-us',('Maryland City','US'):'baltimore-us',('Scaggsville','US'):'baltimore-us',
 ('Jackson','US','New Jersey'):'newyork',
 # in-MSA towns left on default
 ('Marlborough','US','Massachusetts'):'boston',('Duxbury','US'):'boston',('Amesbury','US'):'boston',('Newburyport','US'):'boston',
 ('Gloucester','US','Massachusetts'):'boston',('Franklin','US','Massachusetts'):'boston',('Middleborough','US'):'boston',
 ('Rochester','US','New Hampshire'):'boston',
 ('Fairhaven','US','Massachusetts'):'providence-us',('Narragansett','US'):'providence-us',('South Kingstown','US'):'providence-us',('Westerly','US'):'providence-us',
 ('Wasco','US','Illinois'):'chicago',('DeKalb','US','Illinois'):'chicago',('Huntley','US'):'chicago',
 ('Painesville','US'):'cleveland-us',('Medina','US','Ohio'):'cleveland-us',('Wadsworth','US','Ohio'):'cleveland-us',('Springboro','US','Ohio'):'cincinnati-us',
 ('Elk River','US','Minnesota'):'minneapolis',('Otsego','US','Minnesota'):'minneapolis',('Saint Michael','US','Minnesota'):'minneapolis',
 ('Buffalo','US','Minnesota'):'minneapolis',('Hastings','US','Minnesota'):'minneapolis',('River Falls','US','Wisconsin'):'minneapolis',
 ('Hopatcong Hills','US'):'newyork',('Sparta','US','New Jersey'):'newyork',('Cortlandt Manor','US'):'newyork',('Peekskill','US'):'newyork',
 ('Montclair','US','Virginia'):'washingtondc',('Cherry Hill','US','Virginia'):'washingtondc',('Culpeper','US'):'washingtondc',('Front Royal','US'):'washingtondc',
 ('Banning','US','California'):'riverside-us',('Yucca Valley','US'):'riverside-us',('Twentynine Palms','US'):'riverside-us',
 ('Barstow','US','California'):'riverside-us',('Barstow Heights','US'):'riverside-us',('Blythe','US','California'):'riverside-us',
 ('Cameron Park','US'):'sacramento-us',('Galt','US','California'):'sacramento-us',('South Lake Tahoe','US'):'sacramento-us',('Hollister','US','California'):'sanjose-us',
 ('Lebanon','US','Indiana'):'indianapolis-us',('Shelbyville','US','Indiana'):'indianapolis-us',('Shelbyville','US','Kentucky'):'louisville-us',
 ('El Reno','US'):'oklahomacity-us',('Chickasha','US'):'oklahomacity-us',
 ('Graham','US','Washington'):'seattle',('Arlington','US','Washington'):'seattle',
 ('Greenville','US','Texas'):'dallas',('Lake Jackson','US'):'houston',
 ('Winder','US'):'atlanta',('Aberdeen','US','Maryland'):'baltimore-us',('Dickson','US','Tennessee'):'nashville-us',('Gardner','US','Kansas'):'kansascity-us',
 ('Oconomowoc','US'):'milwaukee-us',('Holland','US','Michigan'):'grandrapids-us',('Green Valley','US','Arizona'):'tucson-us',('Williamsburg','US','Virginia'):'virginiabeach-us',
 ('Tavares','US'):'orlando-us',('Eustis','US'):'orlando-us',('Belle Glade','US'):'miami',('Storrs','US'):'hartford-us',('Mansfield City','US'):'hartford-us',
})
# ---- Canada (StatCan CMAs)
FIX.update({('Brooklin','CA'):'default',('Okotoks','CA'):'default',
            ('Keswick','CA'):'toronto',('Alliston','CA'):'toronto',('Orangeville','CA'):'toronto'})
# ---- Latin America & Caribbean
FIX.update({('Fundão','BR'):'vitoria-br',('Domingos Martins','BR'):'default',('Marechal Floriano','BR'):'default',
            ('Cayey','PR'):'sanjuan-pr',('Manatí','PR'):'sanjuan-pr',('Barceloneta','PR'):'sanjuan-pr',('Humacao','PR'):'sanjuan-pr'})
for _s in [
 ('Puerto Plata','DO'),('La Vega','DO'),('Moca','DO'),('Salcedo','DO'),('Jarabacoa','DO'),('Monte Llano','DO'),('Monte Plata','DO'),('Bayaguana','DO'),
 ('Güines','CU'),('Mariel','CU'),('Guanajay','CU'),('Güira de Melena','CU'),('Alquízar','CU'),('San José de las Lajas','CU'),('Jaruco','CU'),
 ('Santa Cruz del Norte','CU'),('San Antonio de los Baños','CU'),
 ('Granada','NI'),('Masaya','NI'),('Diriamba','NI'),('Jinotepe','NI'),('Masatepe','NI'),('San Marcos','NI'),('Nagarote','NI'),
 ('Antigua Guatemala','GT'),('Ciudad Vieja','GT'),('Jocotenango','GT'),('Alotenango','GT'),('Santa María de Jesús','GT'),('Chimaltenango','GT'),
 ('El Tejar','GT'),('San Andrés Itzapa','GT'),('Sumpango','GT'),('Sanarate','GT'),('Palín','GT'),
 ('Jacmel','HT'),('Fond Parisien','HT'),
 ('Rionegro','CO'),('Marinilla','CO'),('Carmen de Viboral','CO'),('La Ceja','CO'),('La Unión','CO',5.97),('Retiro','CO'),('Fredonia','CO'),
 ('San Vicente','CO',6.28),('Santuario','CO'),
 ('Santander de Quilichao','CO'),('Florida','CO',3.32),('Pradera','CO'),('Miranda','CO'),('El Cerrito','CO'),('Corinto','CO'),('Guacarí','CO'),
 ('Fusagasugá','CO'),('Silvania','CO'),('Pacho','CO'),
 ('Lagos de Moreno','MX'),('Romita','MX'),('Tlaxcala','MX'),('Santa Ana Chiautempan','MX'),('Contla','MX'),('La Magdalena Tlaltelulco','MX'),
 ('Atlixco','MX'),('Apaseo el Grande','MX'),('Apaseo el Alto','MX'),('Yautepec','MX'),
 ('Encarnación de Díaz','MX'),('Villa Hidalgo','MX',21.67),('Rincón de Romos','MX'),('Pabellón de Arteaga','MX'),
 ('Capulhuac de Mirafuentes','MX'),('Xalatlaco','MX'),('Tala','MX'),('Tepeji del Río de Ocampo','MX'),
 ('Morocelí','HN'),('Sabanagrande','HN'),('San Juan de Flores','HN'),
 ('Cabimas','VE'),('Puerto Cabello','VE'),('Milagro','EC'),('Naranjito','EC'),('El Triunfo','EC'),
 ('Zacatecoluca','SV'),('Cojutepeque','SV'),('Aguilares','SV'),('La Libertad','SV'),('Chancay','PE'),
 ('Quillota','CL'),('Limache','CL'),('La Cruz','CL'),('Casablanca','CL'),('Quintero','CL')]:
    FIX[_s]='default'
# ---- Europe (Eurostat FUAs)
FIX.update({('Pulheim','DE'):'koln-de',('Opladen','DE'):'koln-de',('Leichlingen','DE'):'koln-de',('Annemasse','FR'):'geneva'})
for _cc,_ts in [
 ('GB',['Buckley','Flint','Deeside','Hawarden','Chester','Darwen','Accrington','Nelson','York','Coventry','Bedworth','Kenilworth','Nuneaton',
        'Royal Leamington Spa','Warwick','Stratford-upon-Avon','Hinckley','Worcester','Droitwich','Stafford','Swadlincote',
        'Sunderland','Washington','Houghton-Le-Spring','Seaham','Stirling','Falkirk','Trowbridge','Chippenham','Frome']),
 ('CH',['Emmen']),
 ('NL',['Leiden','Merenwijk','Oegstgeest','Leiderdorp','Katwijk aan Zee','Alphen aan den Rijn','Alkmaar','Heiloo','Bergen','Heerhugowaard','Oosterhout']),
 ('DE',['Solingen','Ohligs','Wülfrath','Mönchengladbach','Korschenbroich','Jüchen','Krefeld','Fischeln','Bockum','Uerdingen','Tönisvorst','Willich',
        'Halle (Saale)','Halle-Neustadt','Merseburg','Weißenfels','Bitterfeld-Wolfen','Wolfen','Zeitz','Altenburg',
        'Bonn','Bonn Hardtberg','Alfter','Königswinter','Sankt Augustin','Siegburg','Wachtberg','Meckenheim','Bad Honnef','Hennef (Sieg)','Rheinbach',
        'Wiesbaden','Dotzheim','Biebrich','Taunusstein','Mainz','Gonsenheim','Darmstadt','Arheilgen','Weiterstadt','Griesheim','Pfungstadt',
        'Ober-Ramstadt','Aschaffenburg','Großostheim','Pforzheim','Reutlingen','Pfullingen','Tübingen','Rottenburg']),
 ('FR',['Lens','Avion','Liévin','Hénin-Beaumont','Carvin','Béthune','Douai','Bruay-la-Buissière','Sin-le-Noble','Libourne']),
 ('BE',['Leuven','Blauwput','Heverlee','Kessel-Lo','Herent','Rotselaar','Mechelen','Sint-Katelijne-Waver','Aalst','Haaltert','Lede','Denderleeuw',
        'Sint-Niklaas','Temse','Hamme']),
 ('IT',['Como','Pavia']),('GR',['Kilkís']),('TR',['Sapanca']),('TJ',['Yovon'])]:
    for _t in _ts:
        FIX[(_t,_cc)]='default'
# ---- East Asia (Chinese prefecture cities; Japanese MEAs; OECD FUAs)
FIX.update({('Kunshan','CN'):'suzhou-cn',('Shilong','CN',23.11):'shenzhen',('Lingwu','CN'):'yinchuan-cn',('Tanzhou','CN'):'zhongshan-cn',
 ('Jing’an','CN',22.21):'zhuhai-cn',('Zhenzhou','CN'):'yangzhou-cn',('Jiashan','CN'):'jiaxing-cn',('Haining','CN'):'jiaxing-cn',('Taixing','CN'):'taizhou-cn',
 ('Jōyō','JP'):'kyoto-jp',('Yawata','JP',34.87):'kyoto-jp',('Kyōtanabe','JP'):'kyoto-jp',('Tanabe','JP',34.82):'kyoto-jp',
 ('Akashi','JP'):'kobe-jp',('Sandachō','JP'):'kobe-jp'})
for _s in [('Xiaogan','CN'),('Hanchuan','CN'),('Huanggang','CN',30.45),('Huangzhou','CN'),('Chuzhou','CN'),('Ma’anshan','CN'),('Zhenjiang','CN'),
 ('Deyang','CN'),('Xinxiang','CN'),('Weinan','CN'),('Neijiang','CN'),('Liaoyang','CN'),('Fangchenggang','CN'),('Qingzhou','CN'),('Yidu','CN'),
 ('Gifu','JP'),('Kakamigahara','JP'),('Ōgaki','JP'),('Yokkaichi','JP',34.97),('Suzuka','JP'),('Toyota','JP',35.08),('Okazaki','JP'),
 ('Tsukuba','JP'),('Narita','JP'),('Ōta','JP',36.30),('Ashikaga','JP'),('Kiryū','JP'),('Fukayachō','JP'),
 ('Kurume','JP'),('Iizuka','JP'),('Shimonoseki','JP'),('Ube','JP'),('Ōmuta','JP'),('Honmachi','JP',32.50),
 ('Cheongju-si','KR'),('Gumi','KR'),('Gyeongju','KR'),('Geoje','KR'),('Sinhyeon','KR'),('Kyosai','KR'),('Miaoli','TW'),('Puli','TW')]:
    FIX[_s]='default'
# ---- South & Southeast Asia (census UAs)
FIX.update({('Bedong','MY'):'georgetown-my',('Gurun','MY'):'georgetown-my',('Sepang','MY'):'kualalumpur',('Banting','MY'):'kualalumpur',
 ('Ramanattukara','IN'):'kozhikode-in',('Pattāmbi','IN'):'thrissur-in',('Trittāla','IN'):'thrissur-in',('Muthutala','IN'):'thrissur-in',   # Palakkad towns: keep the Malappuram seed off them
('Gujar Khan','PK'):'islamabad-pk'})
for _s in [('Havelian','PK'),('Iligan City','PH'),('Tarlac City','PH'),('Cuenca','PH'),('Talisay','PH',14.09),
 ('Muhamma','IN'),('Chodavaram','IN',17.83),('Elamanchili','IN'),('Bāndarban','BD'),('Rangamati','BD'),
 ('Bắc Giang','VN'),('Hưng Yên','VN'),('Vĩnh Yên','VN'),('Chí Linh','VN'),('Phổ Yên','VN'),('Thành phố Sông Công','VN')]:
    FIX[_s]='default'
# ---- Middle East & Africa
FIX.update({('Burj al ‘Arab','EG'):'alexandria-eg',('Burj al ‘Arab al Jadīdah','EG'):'alexandria-eg'})
for _s in [('Banhā','EG'),('Kafr ash Shaykh','EG'),('As Salţ','JO'),('Mādabā','JO'),('Jarash','JO'),
 *[(t,'IL') for t in ['Nazareth','Naẕerat ‘Illit','Afula','Kafr Kannā','Yāfā','Ar Rayna','Migdal Ha‘Emeq','Umm el Faḥm','‘Ara-‘Ar‘ara',
                      'Kafr Qari‘','Pardés H̱anna Karkur','Or Akiva','Binyamina-Giv‘at ‘Ada',"Binyamina-Giv'at Ada"]],
 *[(t,'NG') for t in ['Iwo','Ikire','Gbongan','Apomu','Olupona','Ijebu-Igbo','Fiditi']]]:
    FIX[_s]='default'

# ======== Round-3 audit fixes (November 2026) ========
# ---- Mexico: Apaseo el Alto GTO is in ZM Querétaro (Metrópolis de México 2020); Apaseo el Grande stays default
FIX[('Apaseo el Alto','MX')] = 'santiagodequeretaro-mx'
# ---- China
# Wanzhou: 2020 census urban population 1,078,149 (district 1,564,449); separate city ~230 km from Chongqing. Zero the urban subdistrict rows.
DENY.discard('wanzhou-cn')
POP[('Wanzhou','CN')] = 1_078_149
ZERO += [('Taibai','CN',30.82),('Pailou','CN',30.80),('Bai’anba','CN',30.76),('Zhoujiaba','CN',30.84),('Zhonggulou','CN',30.82),
         ('Gaoliang','CN',30.82),('Tiancheng','CN',30.87),('Changling','CN',30.77),('Xintian','CN',30.70),('Shuanghekou','CN',30.75),
         ('Shahe','CN',30.83),('Chenjiaba','CN',30.81),('Wuqiao','CN',30.78),('Jiuchi','CN',30.80),('Gaofeng','CN',30.71)]
# Neijiang, Xinxiang, Zhenjiang: separate prefecture cities whose urban districts clear 1M on the CN urban-district basis
del FIX[('Neijiang','CN')]
SEED.append(dict(sel=('Neijiang','CN'), r=15, force=False, key='neijiang-cn'))
del FIX[('Xinxiang','CN')]
PRECORE.append(dict(sel=('Xinxiang','CN'), r=15, force=False, key='xinxiang-cn'))   # claims before Zhengzhou
del FIX[('Zhenjiang','CN')]
POP[('Zhenjiang','CN')] = 1_266_790    # 2020 census, 3 urban districts
SEED.append(dict(sel=('Zhenjiang','CN'), r=12, force=False, key='zhenjiang-cn'))
# Xiangtan is its own prefecture city, never part of Zhuzhou
for _s in SEED:
    if _s.get('key') == 'zhuzhou-cn':
        _s['r'] = 15
FIX[('Xiangtan','CN')] = 'default'
# ---- India: Vatakara-taluk towns are in the 2011 Kozhikode UA (not Kannur UA, not default); Trikarpur South is Kasaragod district
for _t in ['Badagara','Chōrōd','Edacchēri','Kottappally','Kunnummal','Nādāpuram','Villiappally','Āyanchēri',
           'Azhiyūr','Erāmala','Tūnēri','Chekkiād']:
    FIX[(_t,'IN')] = 'kozhikode-in'
FIX[('Trikarpūr South','IN')] = 'default'
# ---- Pakistan: Haripur district (KP) is outside Islamabad-Rawalpindi; Sargodha-district Sahiwal row carried Sahiwal city's population
FIX.update({('Khalabat','PK'):'default', ('Haripur','PK'):'default'})
POP[('Sahiwal','PK',31.97)] = 50_000
# ---- Europe
DENY |= {'leipzig-de'}   # Eurostat 2021 FUA 956,290
for _t in ['Paderborn','Delbrück','Hövelhof','Bad Lippspringe','Warendorf','Oelde','Georgsmarienhütte','Melle','Bad Essen',
           'Minden','Porta Westfalica','Hille','Lübbecke','Espelkamp']:
    FIX[(_t,'DE')] = 'default'   # outside the Bielefeld FUA (Bielefeld + Gütersloh + Herford + Lippe)
FIX[('Geertruidenberg','NL')] = 'default'   # Breda area, not Rotterdam FUA
for _t in ['Obninsk','Balabanovo','Maloyaroslavets','Strunino','Karabanovo','Aleksandrov','Kirzhach','Petushki','Pokrov','Konakovo']:
    FIX[(_t,'RU')] = 'default'   # outside Moscow city + Moscow Oblast
# ---- Brazil: AU de Jundiaí members
FIX.update({('Itupeva','BR'):'default', ('Louveira','BR'):'default'})
# ---- New 1M+ metros
SEED.append(dict(sel=('Omaha','US'), r=40, key='omaha-us'))   # Omaha-Council Bluffs MSA 1,001,010 (Census V2024)
SEED += [dict(sel=('Hargeysa','SO'), r=25),        # UN WUP: 1.2-1.6M
         dict(sel=('Uyo','NG'), r=30),             # UN WUP 2025 1,567,115
         dict(sel=('Owerri','NG'), r=30),          # UN WUP 2018 ~1.02M
         dict(sel=('Najaf','IQ'), r=20),           # Najaf + Kufa; WUP ~1.02-1.27M
         dict(sel=('Bujumbura','BI'), r=20),       # UN WUP 2025 1,246,960
         dict(sel=('Bobo-Dioulasso','BF'), r=25)]  # UN WUP 2025 1,125,023
# ---- False metros
DENY |= {'hamhung-kp'}   # 2008 census 768,551 incl. Hungnam (DB double-counts Hungnam)
