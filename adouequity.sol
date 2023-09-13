pragma solidity ^0.6.8;

interface AdouToken {
    function transfer(address _to, uint256 _value) external returns (bool success);
    
    function balanceOf(address _owner)  external returns (uint256 balance);
}

abstract contract Token {
    uint256 public totalSupply;

    function balanceOf(address _owner) virtual public view returns (uint256 balance);
    
    function transfer(address _to, uint256 _value) virtual public returns (bool success);

    event Transfer(address indexed _from, address indexed _to, uint256 _value);
}

contract AdouEquity is Token {
    string public name = "ADTȨ��"; //Token����
    string public symbol = "ADE"; //Token���
    uint8 public decimals = 4; //����tokenʹ�õ�С�����λ��������Ϊ4����ʾ֧��0.0001
    address ownerAddr; //ADE��Լ�����ߵ�ַ�����湫�����д�������
    address adtOwnerAddr; //ADT��Լ�����ߵ�ַ
    address teamAddr; //ADT�Ŷӵ�ַ
    address jackpotAddr; //ADT���ص�ַ 
    address reserveAddr; //ADT׼�����ַ 
    address exchangeAddr; //ADT�������Խӵ�ַ�������ַ��
    AdouToken public adtContract; //ADT��Լ����
    uint8 public jackpotLowerLimit = 1; //ADT�������ްٷֱ�
    uint8 public reserveLowerLimit = 50; //ADT׼�������ްٷֱ�
    uint8 public teamProfit = 20; //ADT�Ŷ�����ٷֱ� 100-20ΪADT��������ٷֱ� 20-3-2ΪADT�Ŷӹ�������ٷֱ�
    uint8 public teamTechnologyProfit = 3; //ADT�ŶӼ�������ٷֱ�
    uint8 public teamOperateProfit = 2; //ADT�Ŷ���Ӫ����ٷֱ�
    uint8 public maxLockupYear = 5; //ADE�����������
    uint8 public exchangeQuanlityLimit = 3; //��Ч�����ƶһ����� 
    uint8 public exchangeRate = 1; //ADE�һ�ADT�ٷ�ֵ���ӣ�1(ADE) ��ֵ��ĸ��100(ADT)
    
    struct lockupInfo{
        uint8 exchangeQuanlity; //�Ѷһ����� 
        uint256 startLockupDate; //��ʼ��������
        uint256 endLockupDate; //������������
        uint256 dividendDate; //��Ϣ���ڣ�������㣩
    }
    mapping (address => uint256) balances; //ADE�˻�
    mapping (address => uint256) changeADTAddrs; //����һ�ADT
    mapping (address => uint8) typeFlagAddrs; //�û����ͱ�� 1���Ա 2���û�Ա
    mapping (address => lockupInfo) lockupInfoAddrs; //�û�������Ϣ
    uint256 public borrowADT; //ʵ�ʽ���ADT������ƥ�佻�����Խӵ�ַ��
    uint256 public technologyADT; //��������ADT
    uint256 public OperateADT; //��Ӫ����ADT
    uint256 public validLockupADE; //��Ч����ADE
    uint8 public exchangeYearUpperLimit = 1; //���Ա�һ�ADE���ްٷֱ�
    uint8 public exchangeForeverUpperLimit = 2; //���û�Ա�һ�ADE���ްٷֱ�
    bool public lock = true; //�������ñ��

    constructor (address _teamAddr, address _jackpotAddr, address _reserveAddr, address _exchangeAddr, address _adtOwnerAddr, address _adtAddr) public {
        totalSupply = 10000000 * 10 ** uint256(decimals); //���ó�ʼ����
        balances[msg.sender] = totalSupply; //��ʼtoken����������Ϣ������(��Լ������)
        ownerAddr = msg.sender;
        adtOwnerAddr = _adtOwnerAddr;
        teamAddr = _teamAddr;
        jackpotAddr = _jackpotAddr;
        reserveAddr = _reserveAddr;
        exchangeAddr = _exchangeAddr;
        adtContract = AdouToken(_adtAddr);
    }
   
    function pay() public payable {}
    
    //ȫ��Ȩ�޿��� 
    modifier isOwnerAddr() { 
        require(msg.sender == ownerAddr);
        _;
    }
    
    //ȫ��Ȩ�޿��� 
    modifier isAdtOwnerAddr() { 
        require(msg.sender == adtOwnerAddr);
        _;
    }
    
    //ȫ��Ȩ�޿��� 
    modifier isExchangeAddr() { 
        require(msg.sender == exchangeAddr);
        _;
    }
    
    //ȫ��Ȩ�޿��� 
    modifier isReserveAddr() { 
        require(msg.sender == reserveAddr);
        _;
    }
    
    //ȫ��Ȩ�޿��� 
    modifier isJackpotAddr() { 
        require(msg.sender == jackpotAddr);
        _;
    }
    
    //ȫ��Ȩ�޿��� 
    modifier isTeamAddr() { 
        require(msg.sender == teamAddr);
        _;
    }
    
    //��ȡָ����ַETH�ʲ� 
    function balanceEth(address _owner) public view returns (uint256 balance) {
        return _owner.balance;
    }
    
    //��ȡָ����ַADE�ʲ�
    function balanceOf(address _owner) override public view returns (uint256 balance) {
        return balances[_owner];
    }
    
    //�����û����ͱ�� 1���Ա 2���û�Ա
    function setTypeFlag(address[] memory _setAddrs, uint8 _type) isOwnerAddr public returns (bool success) {
        require(_type >= 1 && _type <= 2);
        require(_setAddrs.length > 0);
        for(uint i = 0; i < _setAddrs.length; i++){
            address addr = _setAddrs[i];
            if(addr != address(0)){
                typeFlagAddrs[addr] = _type;
            }
        }
        return true;
    }
    
    //���û�Ա�һ�ADE���ްٷֱ�
    function setExchangeLimit(uint8 _yearLimit, uint8 _foreverLimit) isOwnerAddr public returns (bool success) {
        require(_yearLimit > 0 && _foreverLimit > 0 && _yearLimit < _foreverLimit);
        exchangeYearUpperLimit = _yearLimit;
        exchangeForeverUpperLimit = _foreverLimit;
        return true;
    }
    
    //�������ֱ��
    function setExchangeBorrow(bool _lock) isOwnerAddr public returns (bool success) {
        lock = _lock;
        return true;
    }
    
    //ETH�ʲ�ת�Ƶ�ָ����ַ
    function transferEth(address _sender) isOwnerAddr public payable returns (bool success) {
        require(_sender != address(0));
        require(ownerAddr.balance > 0);
        require(address(uint160(_sender)).send(ownerAddr.balance));
        return true;
    }
    
    //ADE�ʲ�ת�Ƶ�ָ����ַ��ADE���ף�
    function transfer(address _to, uint256 _value) override public returns (bool success) {
        require(_to != address(0));
        require(now > lockupInfoAddrs[msg.sender].endLockupDate && lockupInfoAddrs[msg.sender].dividendDate >= lockupInfoAddrs[msg.sender].endLockupDate);
        require(balances[msg.sender] >= _value && balances[_to] + _value > balances[_to]);
        balances[msg.sender] -= _value;
        balances[_to] += _value;
        emit Transfer(msg.sender, _to, _value);
        return true;
    }
    
    //���Ŷ��˻�����ADT��������Ա���ͷŹ���
    function allocateTechnology(address[] memory _tos, uint16[] memory _years, uint16[] memory _qualitys, uint256 _tot) isTeamAddr public returns (uint256 technology){
        require(_tot > 0 && technologyADT + _tot <= teamTechnologyProfit * 10000000);
        require(_tos.length > 0 && _tos.length == _years.length && _years.length == _qualitys.length);
        uint16 totYear = 0;
        uint16 totQuality = 0;
        for(uint i = 0; i < _years.length; i++){
            totYear += _years[i];
            totQuality += _qualitys[i];
        }
        require(totYear > 0 && totQuality> 0);
        for(uint i = 0; i < _tos.length; i++){
            address addr = _tos[i];
            if(addr == address(0)){
                continue;
            }
            uint256 adt = _tot * (_years[i] / totYear + _qualitys[i] / totQuality) / 2;
            if(adtContract.transfer(addr, adt)){
                technologyADT += adt;
            }
        }
        return technologyADT;
    }
    
    //���Ŷ��˻�����ADT����Ӫ��Ա���ͷŹ���
    function allocateOperate(address[] memory _tos, uint16[] memory _years, uint16[] memory _qualitys, uint256 _tot) isTeamAddr public returns (uint256 operate){
        require(_tot > 0 && OperateADT + _tot <= teamOperateProfit * 10000000);
        require(_tos.length > 0 && _tos.length == _years.length && _years.length == _qualitys.length);
        uint16 totYear = 0;
        uint16 totQuality = 0;
        for(uint i = 0; i < _years.length; i++){
            totYear += _years[i];
            totQuality += _qualitys[i];
        }
        require(totYear > 0 && totQuality> 0);
        for(uint i = 0; i < _tos.length; i++){
            address addr = _tos[i];
            if(addr == address(0)){
                continue;
            }
            uint256 adt = _tot * (_years[i] / totYear + _qualitys[i] / totQuality) / 2;
            if(adtContract.transfer(addr, adt)){
                OperateADT += adt;
            }
        }
        return OperateADT;
    }
    
    //��adt���˻�����exchangeAddr
    function adtBorrow(uint256 _value) isAdtOwnerAddr public returns (bool success) {
        uint256 borrowUpperLimit  = (teamProfit - teamTechnologyProfit - teamOperateProfit - jackpotLowerLimit) * 10000000;
        require(borrowADT + _value <= borrowUpperLimit && borrowADT + _value > borrowADT);
        uint256 adt = adtContract.balanceOf(msg.sender);
        require(adt >= _value && adt - _value < adt);      
        borrowADT += _value;  
        if(!adtContract.transfer(exchangeAddr, _value)){
            borrowADT -= _value; 
            return false;
        }
        return true;
    }
    
    //��exchangeAddr�黹adt���˻�
    function adtReturn(uint256 _value) isExchangeAddr public returns (bool success) {
        require(borrowADT >= _value && borrowADT - _value < borrowADT);
        uint256 adt = adtContract.balanceOf(msg.sender);
        require(adt >= _value && adt - _value < adt);        
        borrowADT -= _value;
        if(!adtContract.transfer(adtOwnerAddr, _value)){
            borrowADT += _value;  
            return false;
        }
        return true;
    }
    
    //��������������
    function adtToJackport(uint256 _value) isAdtOwnerAddr public returns (bool success) {
        require(_value > 0 && _value <= 800000000);
        return adtContract.transfer(jackpotAddr, _value);
    }
    
    //���佱�����浽�����˻�,_tot������ADT����
    function allocateJackport(address[] memory _dividendAddr, uint256 _tot) isJackpotAddr public returns (bool success) {
        require(_tot > 0 && _tot <= 1000000000);
        require(validLockupADE > 0 && validLockupADE <= 10000000);
        uint256 adt = adtContract.balanceOf(msg.sender);
        require(adt >= _tot * jackpotLowerLimit / 100);
        require(_dividendAddr.length > 0);
        uint256 cancelLockupADE = 0;
        for(uint i = 0; i < _dividendAddr.length; i++){
            address addr = _dividendAddr[i];
            if(addr == address(0)){
                continue;
            }
            if(now < lockupInfoAddrs[addr].dividendDate || lockupInfoAddrs[addr].dividendDate >= lockupInfoAddrs[addr].endLockupDate || balances[addr] <= 0){
                continue;
            }
            uint256 dividend = balances[addr] * adt / validLockupADE;
            //��ʱ����ԭʼ���ݣ��ڷ���ADTʧ��ʱ�ָ�
            uint8 exchangeQuanlity_old = lockupInfoAddrs[addr].exchangeQuanlity; 
            uint256 startLockupDate_old = lockupInfoAddrs[addr].startLockupDate; 
            uint256 endLockupDate_old = lockupInfoAddrs[addr].endLockupDate; 
            uint256 dividendDate_old = lockupInfoAddrs[addr].dividendDate; 
            lockupInfoAddrs[addr].dividendDate += 365 days;
            if(lockupInfoAddrs[addr].dividendDate >= lockupInfoAddrs[addr].endLockupDate){	
                lockupInfoAddrs[addr].startLockupDate = 0;
                lockupInfoAddrs[addr].endLockupDate = 0;
                lockupInfoAddrs[addr].dividendDate = 0;
                lockupInfoAddrs[addr].exchangeQuanlity = 0;
                cancelLockupADE += balances[addr];
            }
            if(!adtContract.transfer(addr, dividend)){
                lockupInfoAddrs[addr].dividendDate = dividendDate_old;
                if(dividendDate_old + 365 days >= endLockupDate_old){	
                    lockupInfoAddrs[addr].startLockupDate = startLockupDate_old;
                    lockupInfoAddrs[addr].endLockupDate = endLockupDate_old;
                    lockupInfoAddrs[addr].exchangeQuanlity = exchangeQuanlity_old;
                    cancelLockupADE -= balances[addr];
                }
            }
        }
        validLockupADE -= cancelLockupADE;
        return true;
    }
    
    //ָ���˻���ȡ׼�����˻�ADT
    function getReserveADT(address _to, uint256 _value) isReserveAddr public returns (bool success) {
        require(_to != address(0));
        uint256 adt = adtContract.balanceOf(msg.sender);
        uint256 adtLimit = adt * reserveLowerLimit / 100;
        require(adt > _value && adt - _value >= adtLimit);
        return adtContract.transfer(_to, _value);
    }
    
    //��˶һ�ADT�ʲ�
    function checkChangeADT(address[] memory _checkAddrs) isReserveAddr public returns (bool success) {
        require(_checkAddrs.length > 0);
        for(uint i = 0; i < _checkAddrs.length; i++){
            address addr = _checkAddrs[i];
            if(addr == address(0)){
                continue;
            }
            if(now <= lockupInfoAddrs[addr].endLockupDate || lockupInfoAddrs[addr].dividendDate < lockupInfoAddrs[addr].endLockupDate || changeADTAddrs[addr] <= 0){
                continue;
            }
            
            uint256 adtReq = changeADTAddrs[addr] * exchangeRate / 100;
            uint256 adtReserve = adtContract.balanceOf(reserveAddr);
            uint256 adtApply = adtContract.balanceOf(addr);
            //��ʱ����ԭʼ���ݣ��ڶһ�ADTʧ��ʱ�ָ�
            uint256 changeADT_old = changeADTAddrs[addr];
            changeADTAddrs[addr] = 0;
            if(adtReserve >= adtReq && adtApply + adtReq > adtApply && adtContract.transfer(addr, adtReq)){                
                emit Transfer(addr, ownerAddr, changeADTAddrs[addr]);
            }else{
                changeADTAddrs[addr] = changeADT_old;
            }
        }
        return true;
    }
    
    //����һ�ADT�ʲ�
    function applyChangeADT(uint256 _value) public returns (uint256 change) {
        require(now > lockupInfoAddrs[msg.sender].endLockupDate && lockupInfoAddrs[msg.sender].dividendDate >= lockupInfoAddrs[msg.sender].endLockupDate);
        require(balances[msg.sender] >= _value && changeADTAddrs[msg.sender] + _value > changeADTAddrs[msg.sender]);
        uint256 adtReq = _value * exchangeRate / 100;
        uint256 adtReserve = adtContract.balanceOf(reserveAddr);
        uint256 adtOwner = adtContract.balanceOf(msg.sender);
        require(adtReserve >= adtReq && adtOwner + adtReq > adtOwner);
        balances[msg.sender] -= _value;
        changeADTAddrs[msg.sender] += _value;
        return changeADTAddrs[msg.sender];
    }
    
    //ADE�ʲ����� 
    function lockupADE(uint8 _lockupYear) public returns (bool success) {
        require(lock);
        require(maxLockupYear >= _lockupYear);
        require(now > lockupInfoAddrs[msg.sender].endLockupDate && lockupInfoAddrs[msg.sender].dividendDate >= lockupInfoAddrs[msg.sender].endLockupDate);
        
        require(lockupInfoAddrs[msg.sender].exchangeQuanlity + 1 <= exchangeQuanlityLimit);
        lockupInfoAddrs[msg.sender].startLockupDate = now;
        lockupInfoAddrs[msg.sender].endLockupDate = now + _lockupYear * 365 days;
        lockupInfoAddrs[msg.sender].dividendDate = now;
        lockupInfoAddrs[msg.sender].exchangeQuanlity += 1;
        validLockupADE += balances[msg.sender];
        return true;
    }
    
    //�һ�ADE�ʲ������� 
    function exchangeLockupADE(uint256 _value, uint8 _lockupYear) public returns (bool success) {
        require(lock);
        require(maxLockupYear >= _lockupYear);
        
        require(lockupInfoAddrs[msg.sender].exchangeQuanlity + 1 <= exchangeQuanlityLimit);
        require(lockupInfoAddrs[msg.sender].startLockupDate == 0 || now < lockupInfoAddrs[msg.sender].startLockupDate + _lockupYear * 365 days);
        uint256 adtReq = _value * exchangeRate / 100;
        uint256 adtReserve = adtContract.balanceOf(reserveAddr);
        uint256 adtOwner = adtContract.balanceOf(msg.sender);
        require(adtOwner >= adtReq && adtReserve + adtReq > adtReserve);
        require(typeFlagAddrs[msg.sender] >= 1 && typeFlagAddrs[msg.sender] <= 2);
        uint256 adeExchangeLimit = totalSupply * exchangeYearUpperLimit / 100;
        if(typeFlagAddrs[msg.sender] == 2){
            adeExchangeLimit = totalSupply * exchangeForeverUpperLimit / 100;
        }
        require(balances[ownerAddr] >= _value && balances[msg.sender] + _value > balances[msg.sender] && balances[msg.sender] + _value <= adeExchangeLimit);
        balances[ownerAddr] -= _value;
        balances[msg.sender] += _value;
        //��ʱ����ԭʼ���ݣ��ڶһ�ADEʧ��ʱ�ָ�
        uint8 exchangeQuanlity_old = lockupInfoAddrs[msg.sender].exchangeQuanlity;
        uint256 startLockupDate_old = lockupInfoAddrs[msg.sender].startLockupDate;
        uint256 dividendDate_old = lockupInfoAddrs[msg.sender].dividendDate;
        lockupInfoAddrs[msg.sender].exchangeQuanlity += 1;
        if(lockupInfoAddrs[msg.sender].startLockupDate == 0){
            lockupInfoAddrs[msg.sender].startLockupDate = now;
            lockupInfoAddrs[msg.sender].dividendDate = now;
        }
        if(!adtContract.transfer(reserveAddr, adtReq)){
            balances[ownerAddr] += _value;
            balances[msg.sender] -= _value;
            lockupInfoAddrs[msg.sender].exchangeQuanlity = exchangeQuanlity_old;
            if(startLockupDate_old == 0){
                lockupInfoAddrs[msg.sender].startLockupDate = startLockupDate_old;
                lockupInfoAddrs[msg.sender].dividendDate = dividendDate_old;
            }
            return false;
        }
        lockupInfoAddrs[msg.sender].endLockupDate = lockupInfoAddrs[msg.sender].startLockupDate + _lockupYear * 365 days;
        validLockupADE += balances[msg.sender];
        emit Transfer(ownerAddr, msg.sender, _value);
        return true;
    }

}