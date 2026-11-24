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
 ('Rhyl','GB'):'default',('Portishead','GB'):'bristol-gb',('Clevedon','GB'):'bristol-gb',('Nailsea','GB'):'bristol-gb',('Burnham-on-Sea','GB'):'bristol-gb',('Loughborough','GB'):'default',('Coalville','GB'):'default',('Melton Mowbray','GB'):'default',('Mountsorrel','GB'):'default',('Wuppertal','DE'):'dusseldorf-de',('Remscheid','DE'):'dusseldorf-de',('Lipa City','PH'):'default',('Tanauan','PH',14.09):'default',('Santo Tomas','PH',14.11):'default',('Malvar','PH'):'default',('Weston-super-Mare','GB'):'bristol-gb',('Prestatyn','GB'):'default',('Lytham St Annes','GB'):'default',
 ('Tarsus','TR'):'mersin-tr',('Manisa','TR'):'default',('Turgutlu','TR'):'default',('Kilis','TR'):'default',
 ('Pazarcık','TR'):'default',('Yalova','TR'):'default',
 # ---- East Asia
 ('Dongguan','CN'):'shenzhen',('Shijie','CN'):'shenzhen',('Zhangjiagang','CN'):'suzhou-cn',('Puning','CN'):'shantou-cn',
 ('Zhubei','TW'):'default',('Zhudong','TW'):'default',('Takamatsu','JP'):'default',('Toyohashi','JP'):'default',('Toyokawa','JP'):'default',
 ('Kusatsu','JP',35.02):'osaka',('Moriyama','JP',35.06):'osaka',('Rittō','JP'):'osaka',('Yasu','JP'):'osaka',('Konan','JP',35.0):'osaka',
 ('Masan','KR'):'busan-kr',('Jiangyin','CN'):'wuxi-cn',('Yixing','CN',31.36):'wuxi-cn',
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
ALIAS={'sungaipetani-my':'georgetown-my','zapopan-mx':'guadalajara-mx','serra-br':'vitoria-br','tellicherry-in':'kannur-in',
       'durgapur-in':'asansol-in','rawalpindi-pk':'islamabad-pk'}

# Separate MSAs next to a built-in metro: the owner's rule is the MSA, so these keep the default scene.
FIX.update({
 ('Boulder','US','Colorado'):'default', ('Layton','US','Utah'):'default', ('Durham','US','North Carolina'):'default',
 ('Racine','US','Wisconsin'):'default', ('Bremerton','US'):'default', ('Oshawa','CA'):'default', ('Whitby','CA'):'default',
})
