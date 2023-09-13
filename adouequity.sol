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
    string public name = "ADT权益"; //Token名称
    string public symbol = "ADE"; //Token简称
    uint8 public decimals = 4; //返回token使用的小数点后几位。如设置为4，表示支持0.0001
    address ownerAddr; //ADE合约创建者地址，保存公开发行代币数量
    address adtOwnerAddr; //ADT合约创建者地址
    address teamAddr; //ADT团队地址
    address jackpotAddr; //ADT奖池地址 
    address reserveAddr; //ADT准备金地址 
    address exchangeAddr; //ADT交易所对接地址（借入地址）
    AdouToken public adtContract; //ADT合约对象
    uint8 public jackpotLowerLimit = 1; //ADT奖池下限百分比
    uint8 public reserveLowerLimit = 50; //ADT准备金下限百分比
    uint8 public teamProfit = 20; //ADT团队收益百分比 100-20为ADT社区收益百分比 20-3-2为ADT团队管理收益百分比
    uint8 public teamTechnologyProfit = 3; //ADT团队技术收益百分比
    uint8 public teamOperateProfit = 2; //ADT团队运营收益百分比
    uint8 public maxLockupYear = 5; //ADE最大锁仓年限
    uint8 public exchangeQuanlityLimit = 3; //有效期限制兑换次数 
    uint8 public exchangeRate = 1; //ADE兑换ADT百分值分子：1(ADE) 分值分母：100(ADT)
    
    struct lockupInfo{
        uint8 exchangeQuanlity; //已兑换次数 
        uint256 startLockupDate; //开始锁定日期
        uint256 endLockupDate; //结束锁定日期
        uint256 dividendDate; //派息日期（按年结算）
    }
    mapping (address => uint256) balances; //ADE账户
    mapping (address => uint256) changeADTAddrs; //申请兑换ADT
    mapping (address => uint8) typeFlagAddrs; //用户类型标记 1年会员 2永久会员
    mapping (address => lockupInfo) lockupInfoAddrs; //用户锁定信息
    uint256 public borrowADT; //实际借入ADT数量（匹配交易所对接地址）
    uint256 public technologyADT; //技术收益ADT
    uint256 public OperateADT; //运营收益ADT
    uint256 public validLockupADE; //有效锁定ADE
    uint8 public exchangeYearUpperLimit = 1; //年会员兑换ADE上限百分比
    uint8 public exchangeForeverUpperLimit = 2; //永久会员兑换ADE上限百分比
    bool public lock = true; //锁仓启用标记

    constructor (address _teamAddr, address _jackpotAddr, address _reserveAddr, address _exchangeAddr, address _adtOwnerAddr, address _adtAddr) public {
        totalSupply = 10000000 * 10 ** uint256(decimals); //设置初始总量
        balances[msg.sender] = totalSupply; //初始token数量给予消息发送者(合约创建者)
        ownerAddr = msg.sender;
        adtOwnerAddr = _adtOwnerAddr;
        teamAddr = _teamAddr;
        jackpotAddr = _jackpotAddr;
        reserveAddr = _reserveAddr;
        exchangeAddr = _exchangeAddr;
        adtContract = AdouToken(_adtAddr);
    }
   
    function pay() public payable {}
    
    //全局权限控制 
    modifier isOwnerAddr() { 
        require(msg.sender == ownerAddr);
        _;
    }
    
    //全局权限控制 
    modifier isAdtOwnerAddr() { 
        require(msg.sender == adtOwnerAddr);
        _;
    }
    
    //全局权限控制 
    modifier isExchangeAddr() { 
        require(msg.sender == exchangeAddr);
        _;
    }
    
    //全局权限控制 
    modifier isReserveAddr() { 
        require(msg.sender == reserveAddr);
        _;
    }
    
    //全局权限控制 
    modifier isJackpotAddr() { 
        require(msg.sender == jackpotAddr);
        _;
    }
    
    //全局权限控制 
    modifier isTeamAddr() { 
        require(msg.sender == teamAddr);
        _;
    }
    
    //获取指定地址ETH资产 
    function balanceEth(address _owner) public view returns (uint256 balance) {
        return _owner.balance;
    }
    
    //获取指定地址ADE资产
    function balanceOf(address _owner) override public view returns (uint256 balance) {
        return balances[_owner];
    }
    
    //设置用户类型标记 1年会员 2永久会员
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
    
    //设置会员兑换ADE上限百分比
    function setExchangeLimit(uint8 _yearLimit, uint8 _foreverLimit) isOwnerAddr public returns (bool success) {
        require(_yearLimit > 0 && _foreverLimit > 0 && _yearLimit < _foreverLimit);
        exchangeYearUpperLimit = _yearLimit;
        exchangeForeverUpperLimit = _foreverLimit;
        return true;
    }
    
    //设置锁仓标记
    function setExchangeBorrow(bool _lock) isOwnerAddr public returns (bool success) {
        lock = _lock;
        return true;
    }
    
    //ETH资产转移到指定地址
    function transferEth(address _sender) isOwnerAddr public payable returns (bool success) {
        require(_sender != address(0));
        require(ownerAddr.balance > 0);
        require(address(uint160(_sender)).send(ownerAddr.balance));
        return true;
    }
    
    //ADE资产转移到指定地址（ADE交易）
    function transfer(address _to, uint256 _value) override public returns (bool success) {
        require(_to != address(0));
        require(now > lockupInfoAddrs[msg.sender].endLockupDate && lockupInfoAddrs[msg.sender].dividendDate >= lockupInfoAddrs[msg.sender].endLockupDate);
        require(balances[msg.sender] >= _value && balances[_to] + _value > balances[_to]);
        balances[msg.sender] -= _value;
        balances[_to] += _value;
        emit Transfer(msg.sender, _to, _value);
        return true;
    }
    
    //从团队账户分配ADT给技术人员（释放规则）
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
    
    //从团队账户分配ADT给运营人员（释放规则）
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
    
    //从adt主账户借入exchangeAddr
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
    
    //从exchangeAddr归还adt主账户
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
    
    //收益上链到奖池
    function adtToJackport(uint256 _value) isAdtOwnerAddr public returns (bool success) {
        require(_value > 0 && _value <= 800000000);
        return adtContract.transfer(jackpotAddr, _value);
    }
    
    //分配奖池收益到锁仓账户,_tot已生产ADT总量
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
            //临时储存原始数据，在分配ADT失败时恢复
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
    
    //指定账户获取准备金账户ADT
    function getReserveADT(address _to, uint256 _value) isReserveAddr public returns (bool success) {
        require(_to != address(0));
        uint256 adt = adtContract.balanceOf(msg.sender);
        uint256 adtLimit = adt * reserveLowerLimit / 100;
        require(adt > _value && adt - _value >= adtLimit);
        return adtContract.transfer(_to, _value);
    }
    
    //审核兑换ADT资产
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
            //临时储存原始数据，在兑换ADT失败时恢复
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
    
    //申请兑换ADT资产
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
    
    //ADE资产锁定 
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
    
    //兑换ADE资产并锁定 
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
        //临时储存原始数据，在兑换ADE失败时恢复
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